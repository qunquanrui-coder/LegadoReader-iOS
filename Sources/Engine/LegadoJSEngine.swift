import Foundation
import CryptoKit

/// State belongs to one source/request pipeline, never to the singleton engine.
/// A cancelled or finished request releases its variables together with this object.
public final class LegadoJSSession: @unchecked Sendable {
    public let sourceIdentifier: String
    public let timeLimit: TimeInterval
    fileprivate let executionLock = NSLock()
    fileprivate var variables: [String: String] = [:]
    fileprivate var remainingExecutionTime: TimeInterval = 1
    fileprivate var remainingEvaluations = 512
    private let stateLock = NSLock()
    private var cancelled = false
    private var failure: SourceScriptError?

    public init(sourceIdentifier: String, timeLimit: TimeInterval = 0.15) {
        self.sourceIdentifier = sourceIdentifier
        self.timeLimit = max(0.01, min(1, timeLimit))
    }
    public var isCancelled: Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return cancelled
    }
    public var firstFailure: SourceScriptError? {
        stateLock.lock(); defer { stateLock.unlock() }; return failure
    }
    fileprivate func record(_ error: SourceScriptError) {
        stateLock.lock(); defer { stateLock.unlock() }
        if failure == nil { failure = error }
    }
    public func cancel() {
        stateLock.lock(); cancelled = true; failure = .cancelled; stateLock.unlock()
        executionLock.lock(); variables.removeAll(); executionLock.unlock()
    }
}

/// Only bounded field/URL expressions are supported. Arbitrary JavaScript is not executed.
/// The iOS public JavaScriptCore API has no script termination operation, so this implementation
/// parses a whitelist AST instead of relying on private watchdog APIs or abandoned worker threads.
public final class LegadoJSEngine {
    public static let shared = LegadoJSEngine()
    @TaskLocal public static var currentSession: LegadoJSSession?
    private init() {}

    public static func identifier(for source: BookSource) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(source)) ?? Data(source.bookSourceUrl.utf8)
        return source.bookSourceUrl + "#" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public func withSession<T>(source: BookSource, operation: () throws -> T) rethrows -> T {
        let identifier = Self.identifier(for: source)
        if let current = Self.currentSession, current.sourceIdentifier == identifier { return try operation() }
        return try Self.$currentSession.withValue(LegadoJSSession(sourceIdentifier: identifier), operation: operation)
    }
    public func withSession<T>(source: BookSource, operation: () async throws -> T) async rethrows -> T {
        let identifier = Self.identifier(for: source)
        if let current = Self.currentSession, current.sourceIdentifier == identifier { return try await operation() }
        return try await Self.$currentSession.withValue(LegadoJSSession(sourceIdentifier: identifier), operation: operation)
    }
    public func throwIfSessionFailed() throws {
        guard let failure = Self.currentSession?.firstFailure else { return }
        if failure == .cancelled { throw CancellationError() }
        throw failure
    }
    public func unsupportedReason(script: String) -> String? {
        do { var parser = try SourceExpressionParser(script); let program = try parser.program(); try Self.validate(program); return nil }
        catch { return error.localizedDescription }
    }
    private static func validate(_ program: [SourceExpressionStatement]) throws {
        let globals = Set(["String", "Number", "parseInt"])
        let methods = Set(["trim", "toLowerCase", "toUpperCase", "toString", "startsWith", "endsWith", "includes", "indexOf", "substring", "slice", "charAt", "split", "join", "replace", "replaceAll", "match"])
        let native: [String: Set<String>] = ["java": ["put", "get", "encodeURI", "base64Encode", "base64Decode", "md5Encode", "md5Encode16", "t2s", "s2t"], "cache": ["put", "get"], "Math": ["floor", "ceil", "round", "abs", "min", "max"], "JSON": ["parse", "stringify"]]
        func visit(_ expression: SourceExpression) throws {
            switch expression {
            case .call(let callee, let arguments):
                if case .variable(let name) = callee {
                    guard globals.contains(name) else { throw SourceScriptError.unsupported("函数 \(name)") }
                } else if case .member(let base, let name) = callee {
                    if case .variable(let namespace) = base, let names = native[namespace] {
                        guard names.contains(name) else { throw SourceScriptError.unsupported("桥接 \(namespace).\(name)") }
                    } else { guard methods.contains(name) else { throw SourceScriptError.unsupported("方法 \(name)") }; try visit(base) }
                } else { throw SourceScriptError.unsupported("动态函数调用") }
                try arguments.forEach(visit)
            case .array(let values): try values.forEach(visit)
            case .unary(_, let child), .member(let child, _): try visit(child)
            case .binary(_, let left, let right), .index(let left, let right): try visit(left); try visit(right)
            case .conditional(let condition, let positive, let negative): try visit(condition); try visit(positive); try visit(negative)
            default: break
            }
        }
        for statement in program { try visit(statement.expression) }
    }
    public func evaluate(script: String, result: String? = nil, baseUrl: String = "", key: String = "", page: Int = 1,
                         session explicitSession: LegadoJSSession? = nil) -> String? {
        let session = explicitSession ?? Self.currentSession ?? LegadoJSSession(sourceIdentifier: "isolated:" + UUID().uuidString)
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return result }
        do {
            var parser = try SourceExpressionParser(trimmed)
            let program = try parser.program()
            try Self.validate(program)
            session.executionLock.lock(); defer { session.executionLock.unlock() }
            if session.isCancelled || Task.isCancelled { throw SourceScriptError.cancelled }
            if let failure = session.firstFailure { throw failure }
            guard session.remainingExecutionTime > 0, session.remainingEvaluations > 0 else { throw SourceScriptError.budgetExceeded }
            session.remainingEvaluations -= 1
            let started = ProcessInfo.processInfo.systemUptime
            defer { session.remainingExecutionTime -= ProcessInfo.processInfo.systemUptime - started }
            let evaluator = try SourceExpressionEvaluator(result: result, baseURL: baseUrl,
                sourceURL: session.sourceIdentifier.components(separatedBy: "#").first ?? baseUrl,
                key: key, page: page, storedVariables: session.variables,
                timeLimit: min(session.timeLimit, session.remainingExecutionTime), cancelled: { session.isCancelled })
            let output = try evaluator.run(program)
            session.variables = evaluator.storedVariables
            return output
        } catch let error as SourceScriptError { session.record(error); return nil }
        catch { session.record(.unsupported(error.localizedDescription)); return nil }
    }

    public func replacePattern(_ pattern: String, in text: String, with replacement: String) -> String? {
        do {
            let evaluator = try SourceExpressionEvaluator(result: text, baseURL: "", sourceURL: "", key: "", page: 1,
                storedVariables: [:], timeLimit: Self.currentSession?.timeLimit ?? 0.15,
                cancelled: { Self.currentSession?.isCancelled ?? false })
            let expression = SourceExpression.call(.member(.literal(.text(text)), "replaceAll"),
                [.literal(.regex(pattern, "g")), .literal(.text(replacement))])
            return try evaluator.run([SourceExpressionStatement(assignment: nil, expression: expression, returns: true)])
        } catch let error as SourceScriptError { Self.currentSession?.record(error); return nil }
        catch { Self.currentSession?.record(.unsupported("正则表达式")); return nil }
    }

    public func unsupportedRuleReason(_ rule: String?) -> String? {
        guard let rule else { return nil }
        guard rule.utf8.count <= 65_536 else { return SourceScriptError.budgetExceeded.localizedDescription }
        for script in splitSelectorAndJS(rule).scripts {
            if let reason = unsupportedReason(script: script) { return reason }
        }
        return nil
    }

    public func hasInlineExpressions(_ template: String) -> Bool {
        let plain = template.replacingOccurrences(of: "{{key}}", with: "").replacingOccurrences(of: "{{page}}", with: "")
        return plain.contains("{{")
    }

    public func unsupportedURLTemplateReason(_ template: String) -> String? {
        guard template.utf8.count <= 16_384 else { return SourceScriptError.budgetExceeded.localizedDescription }
        if let reason = unsupportedRuleReason(template) { return reason }
        if let regex = try? NSRegularExpression(pattern: "\\{\\{([^{}]+)\\}\\}") {
            for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
                guard let range = Range(match.range(at: 1), in: template) else { continue }
                let expression = String(template[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if expression != "key" && expression != "page", let reason = unsupportedReason(script: expression) { return reason }
            }
        }
        return nil
    }

    /// Splits a Legado rule into `(selectorPart, [jsSnippets])` if it contains `@js:` or `<js>...</js>`.
    public func splitSelectorAndJS(_ rawRule: String) -> (selector: String, scripts: [String]) {
        guard rawRule.utf8.count <= 65_536 else { Self.currentSession?.record(.budgetExceeded); return ("", []) }
        var working = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        var scripts: [String] = []
        
        // Extract <js>...</js> blocks
        let tagPattern = "<js>([\\s\\S]*?)</js>"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: working, range: NSRange(working.startIndex..., in: working))
            for m in matches {
                if let r = Range(m.range(at: 1), in: working) {
                    scripts.append(String(working[r]))
                }
            }
            working = regex.stringByReplacingMatches(in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "")
        }
        
        // Extract trailing @js:...
        if let jsRange = working.range(of: "@js:", options: .caseInsensitive) {
            let jsCode = String(working[jsRange.upperBound...])
            scripts.append(jsCode)
            working = String(working[..<jsRange.lowerBound])
        }
        
        return (working.trimmingCharacters(in: .whitespacesAndNewlines), scripts)
    }
    
    /// Evaluates inline `{{...}}` expressions as well as `@js:` / `<js>` blocks inside URL templates (like `searchUrl`).
    public func renderUrlTemplate(_ template: String, baseUrl: String, key: String, page: Int = 1) -> String {
        guard template.utf8.count <= 16_384 else { Self.currentSession?.record(.budgetExceeded); return "" }
        let (basePart, scripts) = splitSelectorAndJS(template)
        var rendered = basePart
        
        // Replace {{...}} expressions
        let inlinePattern = "\\{\\{([^{}]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: inlinePattern) {
            let matches = regex.matches(in: rendered, range: NSRange(rendered.startIndex..., in: rendered)).reversed()
            for m in matches {
                guard let fullRange = Range(m.range(at: 0), in: rendered),
                      let exprRange = Range(m.range(at: 1), in: rendered) else { continue }
                let expr = String(rendered[exprRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if expr == "key" {
                    let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                    rendered.replaceSubrange(fullRange, with: encoded)
                } else if expr == "page" {
                    rendered.replaceSubrange(fullRange, with: "\(page)")
                } else if let jsOut = evaluate(script: expr, result: key, baseUrl: baseUrl, key: key, page: page) {
                    rendered.replaceSubrange(fullRange, with: jsOut)
                }
            }
        }
        
        for script in scripts {
            if let jsOut = evaluate(script: script, result: rendered, baseUrl: baseUrl, key: key, page: page) {
                rendered = jsOut
            }
        }
        return rendered
    }
}
