import Foundation
import CoreFoundation
import CryptoKit

/// A deliberately small expression language for community-source field/URL transforms.
/// Source text is parsed into this AST; it is never passed to eval/JavaScriptCore.
/// No user functions, loops, dynamic code or arbitrary object methods exist in the language.
public enum SourceScriptError: LocalizedError, Equatable {
    case unsupported(String)
    case budgetExceeded
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unsupported(let detail): return "书源脚本暂不支持：\(detail)"
        case .budgetExceeded: return "书源脚本超出执行或数据预算，已停止。"
        case .cancelled: return "书源脚本已取消。"
        }
    }
}

enum SourceExpressionValue {
    case text(String), number(Double), bool(Bool), array([SourceExpressionValue])
    case object([String: SourceExpressionValue]), regex(String, String), null

    var string: String {
        switch self {
        case .text(let text): return text
        case .number(let number): return number.isFinite && number.rounded() == number ? String(format: "%.0f", number) : String(number)
        case .bool(let value): return value ? "true" : "false"
        case .array(let values): return values.map { $0 == .null ? "" : $0.string }.joined(separator: ",")
        case .object: return "[object Object]"
        case .regex(let pattern, let flags): return "/\(pattern)/\(flags)"
        case .null: return ""
        }
    }
    var numeric: Double { Double(string) ?? (string.isEmpty ? 0 : .nan) }
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .text(let value): return !value.isEmpty
        default: return true
        }
    }
}

extension SourceExpressionValue: Equatable {}

indirect enum SourceExpression {
    case literal(SourceExpressionValue), variable(String), array([SourceExpression])
    case unary(String, SourceExpression), binary(String, SourceExpression, SourceExpression)
    case conditional(SourceExpression, SourceExpression, SourceExpression)
    case member(SourceExpression, String), index(SourceExpression, SourceExpression)
    case call(SourceExpression, [SourceExpression])
}

struct SourceExpressionStatement {
    let assignment: String?
    let expression: SourceExpression
    let returns: Bool
}

struct SourceExpressionParser {
    enum Token: Equatable { case word(String), text(String), number(Double), regex(String, String), symbol(String), end }
    private var tokens: [Token] = []
    private var position = 0
    private var depth = 0
    private static let denied = Set(["while", "for", "do", "function", "class", "new", "eval", "Function", "Proxy", "Reflect", "this", "globalThis", "window", "self", "import", "export", "with", "try", "throw", "async", "await", "yield", "delete"])

    init(_ script: String) throws {
        guard script.utf8.count <= 16_384 else { throw SourceScriptError.budgetExceeded }
        let characters = Array(script)
        var index = 0
        var canStartLiteral = true
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
        while index < characters.count {
            if tokens.count >= 4096 { throw SourceScriptError.budgetExceeded }
            let c = characters[index]
            if c.isWhitespace { index += 1; continue }
            if c == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                index += 2
                while index < characters.count && characters[index] != "\n" { index += 1 }
                continue
            }
            if c == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                index += 2
                while index + 1 < characters.count && !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                guard index + 1 < characters.count else { throw SourceScriptError.unsupported("未结束的注释") }
                index += 2; continue
            }
            if c == "\"" || c == "'" {
                let quote = c
                index += 1
                var value = ""
                while index < characters.count && characters[index] != quote {
                    if characters[index] == "\\" {
                        index += 1
                        guard index < characters.count else { throw SourceScriptError.unsupported("未结束的字符串") }
                        switch characters[index] {
                        case "n": value += "\n"
                        case "r": value += "\r"
                        case "t": value += "\t"
                        case "u":
                            guard index + 4 < characters.count,
                                  let number = UInt32(String(characters[(index + 1)...(index + 4)]), radix: 16),
                                  let scalar = UnicodeScalar(number) else { throw SourceScriptError.unsupported("Unicode 转义") }
                            value.unicodeScalars.append(scalar); index += 4
                        default: value.append(characters[index])
                        }
                    } else { value.append(characters[index]) }
                    index += 1
                }
                guard index < characters.count else { throw SourceScriptError.unsupported("未结束的字符串") }
                index += 1; tokens.append(.text(value)); canStartLiteral = false; continue
            }
            if c.isNumber || (c == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                let start = index
                while index < characters.count && (characters[index].isNumber || characters[index] == ".") { index += 1 }
                guard let number = Double(String(characters[start..<index])), number.isFinite else { throw SourceScriptError.unsupported("数字") }
                tokens.append(.number(number)); canStartLiteral = false; continue
            }
            if c.isLetter || c == "_" || c == "$" {
                let start = index
                while index < characters.count && isWord(characters[index]) { index += 1 }
                let word = String(characters[start..<index])
                guard !Self.denied.contains(word) else { throw SourceScriptError.unsupported("循环、函数或动态执行（\(word)）") }
                tokens.append(.word(word)); canStartLiteral = ["var", "let", "const", "return"].contains(word); continue
            }
            if c == "/" && canStartLiteral {
                index += 1
                var pattern = ""
                var inClass = false
                while index < characters.count {
                    let value = characters[index]
                    if value == "\\" {
                        guard index + 1 < characters.count else { throw SourceScriptError.unsupported("正则转义") }
                        pattern.append(value); index += 1; pattern.append(characters[index]); index += 1; continue
                    }
                    if value == "[" { inClass = true }
                    if value == "]" { inClass = false }
                    if value == "/" && !inClass { break }
                    pattern.append(value); index += 1
                }
                guard index < characters.count, pattern.utf8.count <= 512 else { throw SourceScriptError.unsupported("正则长度或结束符") }
                index += 1
                var flags = ""
                while index < characters.count && characters[index].isLetter { flags.append(characters[index]); index += 1 }
                guard flags.allSatisfy({ "gim".contains($0) }) else { throw SourceScriptError.unsupported("正则标记") }
                tokens.append(.regex(pattern, flags)); canStartLiteral = false; continue
            }
            let nextThree = String(characters[index..<min(index + 3, characters.count)])
            let nextTwo = String(characters[index..<min(index + 2, characters.count)])
            let symbol: String
            if ["===", "!=="].contains(nextThree) { symbol = nextThree; index += 3 }
            else if ["&&", "||", "==", "!=", "<=", ">="].contains(nextTwo) { symbol = nextTwo; index += 2 }
            else if "()[];,.?:+-*/%!<>=\n".contains(c) { symbol = String(c); index += 1 }
            else { throw SourceScriptError.unsupported("符号 \(c)") }
            tokens.append(.symbol(symbol))
            canStartLiteral = !["(", "["].contains(symbol) ? ![")", "]", "."].contains(symbol) : true
        }
        tokens.append(.end)
    }

    private var current: Token { tokens[position] }
    private mutating func take(_ symbol: String) -> Bool {
        if current == .symbol(symbol) { position += 1; return true }; return false
    }
    private mutating func expect(_ symbol: String) throws {
        guard take(symbol) else { throw SourceScriptError.unsupported("预期 \(symbol)") }
    }
    mutating func program() throws -> [SourceExpressionStatement] {
        var result: [SourceExpressionStatement] = []
        while current != .end {
            if take(";") { continue }
            guard result.count < 128 else { throw SourceScriptError.budgetExceeded }
            var assignment: String?
            var returns = false
            if case .word(let word) = current, ["var", "let", "const"].contains(word) {
                position += 1
                guard case .word(let name) = current else { throw SourceScriptError.unsupported("变量名") }
                position += 1; assignment = name; try expect("=")
            } else if current == .word("return") { position += 1; returns = true }
            else if case .word(let name) = current, position + 1 < tokens.count, tokens[position + 1] == .symbol("=") {
                assignment = name; position += 2
            }
            let value = try expression()
            result.append(SourceExpressionStatement(assignment: assignment, expression: value, returns: returns))
            if current != .end && !take(";") { throw SourceScriptError.unsupported("语句分隔或复合语句") }
        }
        return result
    }
    private mutating func expression(_ minimum: Int = 0) throws -> SourceExpression {
        depth += 1
        defer { depth -= 1 }
        guard depth <= 32 else { throw SourceScriptError.budgetExceeded }
        var value: SourceExpression
        if take("!") { value = .unary("!", try expression(8)) }
        else if take("-") { value = .unary("-", try expression(8)) }
        else if take("+") { value = .unary("+", try expression(8)) }
        else { value = try primary() }
        let precedence = ["||": 1, "&&": 2, "==": 3, "!=": 3, "===": 3, "!==": 3,
                          "<": 4, ">": 4, "<=": 4, ">=": 4, "+": 5, "-": 5, "*": 6, "/": 6, "%": 6]
        while case .symbol(let op) = current, let rank = precedence[op], rank >= minimum {
            position += 1
            value = .binary(op, value, try expression(rank + 1))
        }
        if minimum == 0 && take("?") {
            let positive = try expression(); try expect(":")
            value = .conditional(value, positive, try expression())
        }
        return value
    }
    private mutating func primary() throws -> SourceExpression {
        var value: SourceExpression
        switch current {
        case .text(let text): value = .literal(.text(text)); position += 1
        case .number(let number): value = .literal(.number(number)); position += 1
        case .regex(let pattern, let flags): value = .literal(.regex(pattern, flags)); position += 1
        case .word(let word):
            position += 1
            if word == "true" || word == "false" { value = .literal(.bool(word == "true")) }
            else if word == "null" || word == "undefined" { value = .literal(.null) }
            else { value = .variable(word) }
        case .symbol("("):
            position += 1; value = try expression(); try expect(")")
        case .symbol("["):
            position += 1
            var values: [SourceExpression] = []
            while current != .symbol("]") {
                if current == .symbol(",") { values.append(.literal(.null)); position += 1; continue }
                values.append(try expression())
                if !take(",") { break }
            }
            try expect("]"); value = .array(values)
        default: throw SourceScriptError.unsupported("表达式")
        }
        while true {
            if take(".") {
                guard case .word(let name) = current else { throw SourceScriptError.unsupported("属性名") }
                position += 1; value = .member(value, name)
            } else if take("[") { let index = try expression(); try expect("]"); value = .index(value, index) }
            else if take("(") {
                var arguments: [SourceExpression] = []
                if current != .symbol(")") {
                    repeat { arguments.append(try expression()); guard arguments.count <= 16 else { throw SourceScriptError.budgetExceeded } } while take(",")
                }
                try expect(")"); value = .call(value, arguments)
            } else { break }
        }
        return value
    }
}

final class SourceExpressionEvaluator {
    static let maximumStringLength = 2_000_000
    private let deadline: TimeInterval
    private var remaining = 8192
    private let cancelled: () -> Bool
    private var locals: [String: SourceExpressionValue]
    var storedVariables: [String: String]

    init(result: String?, baseURL: String, sourceURL: String, key: String, page: Int,
         storedVariables: [String: String], timeLimit: TimeInterval, cancelled: @escaping () -> Bool) throws {
        deadline = ProcessInfo.processInfo.systemUptime + max(0.01, min(1, timeLimit))
        self.cancelled = cancelled
        self.storedVariables = storedVariables
        guard [result ?? "", baseURL, sourceURL, key].allSatisfy({ $0.utf16.count <= Self.maximumStringLength }) else { throw SourceScriptError.budgetExceeded }
        locals = ["result": .text(result ?? ""), "src": .text(result ?? ""), "baseUrl": .text(baseURL),
                  "sourceUrl": .text(sourceURL), "key": .text(key), "page": .number(Double(page))]
    }
    private func tick() throws {
        remaining -= 1
        if cancelled() || Task.isCancelled { throw SourceScriptError.cancelled }
        if remaining < 0 || ProcessInfo.processInfo.systemUptime > deadline { throw SourceScriptError.budgetExceeded }
    }
    private func bounded(_ string: String) throws -> SourceExpressionValue {
        guard string.utf16.count <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
        return .text(string)
    }
    func run(_ program: [SourceExpressionStatement]) throws -> String? {
        var result: SourceExpressionValue = .null
        for statement in program {
            try tick()
            result = try evaluate(statement.expression)
            if let name = statement.assignment {
                guard !["java", "cache", "Math", "JSON", "String", "Number", "parseInt"].contains(name) else { throw SourceScriptError.unsupported("覆盖内置名称") }
                locals[name] = result
            }
            if statement.returns { break }
        }
        try tick()
        guard result != .null else { return nil }
        return try bounded(result.string).string
    }
    private func evaluate(_ expression: SourceExpression) throws -> SourceExpressionValue {
        try tick()
        switch expression {
        case .literal(let value): return value
        case .variable(let name): return locals[name] ?? .null
        case .array(let values):
            var result: [SourceExpressionValue] = []
            var length = 0
            for value in values {
                try tick()
                let item = try evaluate(value)
                length += item.string.utf16.count + 1
                guard result.count < 4096, length <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
                result.append(item)
            }
            return .array(result)
        case .unary(let op, let child):
            let value = try evaluate(child)
            return op == "!" ? .bool(!value.truthy) : .number(op == "-" ? -value.numeric : value.numeric)
        case .conditional(let condition, let positive, let negative): return try evaluate(evaluate(condition).truthy ? positive : negative)
        case .binary(let op, let lhs, let rhs):
            let left = try evaluate(lhs)
            if op == "||" { return left.truthy ? left : try evaluate(rhs) }
            if op == "&&" { return left.truthy ? try evaluate(rhs) : left }
            let right = try evaluate(rhs)
            switch op {
            case "+":
                if case .text = left { return try concatenate(left.string, right.string) }
                if case .text = right { return try concatenate(left.string, right.string) }
                return .number(left.numeric + right.numeric)
            case "-": return .number(left.numeric - right.numeric)
            case "*": return .number(left.numeric * right.numeric)
            case "/": return .number(left.numeric / right.numeric)
            case "%": return .number(left.numeric.truncatingRemainder(dividingBy: right.numeric))
            case "==", "===": return .bool(left == right || (op == "==" && left.string == right.string))
            case "!=", "!==": return .bool(!(left == right || (op == "!=" && left.string == right.string)))
            case "<": return .bool(left.numeric < right.numeric)
            case ">": return .bool(left.numeric > right.numeric)
            case "<=": return .bool(left.numeric <= right.numeric)
            case ">=": return .bool(left.numeric >= right.numeric)
            default: throw SourceScriptError.unsupported("运算符")
            }
        case .member(let base, let name):
            let value = try evaluate(base)
            if name == "length" {
                if case .array(let values) = value { return .number(Double(values.count)) }
                return .number(Double(value.string.utf16.count))
            }
            if case .object(let object) = value { return object[name] ?? .null }
            throw SourceScriptError.unsupported("属性 \(name)")
        case .index(let base, let index):
            let value = try evaluate(base), item = try evaluate(index)
            if case .object(let object) = value { return object[item.string] ?? .null }
            let number = try integer(item)
            if case .array(let values) = value { return values.indices.contains(number) ? values[number] : .null }
            let text = value.string as NSString
            return number >= 0 && number < text.length ? .text(text.substring(with: NSRange(location: number, length: 1))) : .null
        case .call(let callee, let arguments):
            let values = try arguments.map(evaluate)
            if case .variable(let name) = callee { return try global(name, values) }
            if case .member(let base, let name) = callee {
                if case .variable(let namespace) = base, ["java", "cache", "Math", "JSON"].contains(namespace) { return try native(namespace, name, values) }
                return try method(evaluate(base), name, values)
            }
            throw SourceScriptError.unsupported("动态函数调用")
        }
    }
    private func concatenate(_ lhs: String, _ rhs: String) throws -> SourceExpressionValue {
        guard lhs.utf16.count + rhs.utf16.count <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
        return .text(lhs + rhs)
    }
    private func integer(_ value: SourceExpressionValue) throws -> Int {
        let number = value.numeric
        guard number.isFinite, abs(number) < 10_000_000 else { throw SourceScriptError.budgetExceeded }
        return Int(number)
    }
    private func global(_ name: String, _ args: [SourceExpressionValue]) throws -> SourceExpressionValue {
        let value = args.first ?? .null
        switch name {
        case "String": return try bounded(value.string)
        case "Number": return .number(value.numeric)
        case "parseInt":
            let radix = args.count > 1 ? try integer(args[1]) : 10
            guard (2...36).contains(radix) else { return .number(.nan) }
            var prefix = ""
            for char in value.string.trimmingCharacters(in: .whitespacesAndNewlines) {
                try tick()
                if prefix.isEmpty && (char == "-" || char == "+") { prefix.append(char) }
                else if Int(String(char), radix: radix) != nil { prefix.append(char) }
                else { break }
            }
            return .number(Int(prefix, radix: radix).map { Double($0) } ?? .nan)
        default: throw SourceScriptError.unsupported("函数 \(name)")
        }
    }
    private func native(_ namespace: String, _ name: String, _ args: [SourceExpressionValue]) throws -> SourceExpressionValue {
        let value = args.first ?? .null
        if namespace == "java" || namespace == "cache" {
            switch name {
            case "put":
                guard args.count == 2, value.string.utf8.count <= 256,
                      args[1].string.utf8.count <= 65_536,
                      storedVariables.count < 128 || storedVariables[value.string] != nil else { throw SourceScriptError.budgetExceeded }
                let total = storedVariables.reduce(0) { $0 + $1.value.utf8.count } - (storedVariables[value.string]?.utf8.count ?? 0) + args[1].string.utf8.count
                guard total <= 262_144 else { throw SourceScriptError.budgetExceeded }
                storedVariables[value.string] = args[1].string; return args[1]
            case "get": return .text(storedVariables[value.string] ?? "")
            case "encodeURI":
                if args.count > 1 && args[1].string.lowercased().contains("gb") {
                    let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
                    guard let data = value.string.data(using: String.Encoding(rawValue: encoding)), data.count <= Self.maximumStringLength / 3 else { throw SourceScriptError.budgetExceeded }
                    let hex = Array("0123456789ABCDEF")
                    var result = ""
                    result.reserveCapacity(data.count * 3)
                    for (index, byte) in data.enumerated() {
                        if index % 1024 == 0 { try tick() }
                        result.append("%"); result.append(hex[Int(byte >> 4)]); result.append(hex[Int(byte & 15)])
                    }
                    return try bounded(result)
                }
                guard value.string.utf8.count <= Self.maximumStringLength / 3 else { throw SourceScriptError.budgetExceeded }
                return try bounded(value.string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value.string)
            case "base64Encode":
                guard value.string.utf8.count <= Self.maximumStringLength / 2 else { throw SourceScriptError.budgetExceeded }
                return try bounded(Data(value.string.utf8).base64EncodedString())
            case "base64Decode": return try bounded(Data(base64Encoded: value.string).flatMap { String(data: $0, encoding: .utf8) } ?? "")
            case "md5Encode", "md5Encode16":
                let hash = Insecure.MD5.hash(data: Data(value.string.utf8)).map { String(format: "%02x", $0) }.joined()
                return .text(name == "md5Encode16" ? String(hash.dropFirst(8).prefix(16)) : hash)
            case "t2s", "s2t":
                guard value.string.utf16.count <= 65_536 else { throw SourceScriptError.budgetExceeded }
                let transform = name == "t2s" ? "Traditional-Simplified" : "Simplified-Traditional"
                return try bounded(value.string.applyingTransform(StringTransform(transform), reverse: false) ?? value.string)
            default: throw SourceScriptError.unsupported("桥接 \(namespace).\(name)")
            }
        }
        if namespace == "Math" {
            switch name {
            case "floor": return .number(floor(value.numeric))
            case "ceil": return .number(ceil(value.numeric))
            case "round": return .number(value.numeric.rounded())
            case "abs": return .number(abs(value.numeric))
            case "min": return .number(args.map(\.numeric).min() ?? .nan)
            case "max": return .number(args.map(\.numeric).max() ?? .nan)
            default: throw SourceScriptError.unsupported("Math.\(name)")
            }
        }
        if namespace == "JSON" {
            if name == "parse" {
                guard value.string.utf8.count <= 262_144, let data = value.string.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { throw SourceScriptError.unsupported("JSON 数据") }
                return try fromJSON(object, depth: 0)
            }
            if name == "stringify" {
                let object = try toJSON(value, depth: 0)
                guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]),
                      let string = String(data: data, encoding: .utf8) else { throw SourceScriptError.unsupported("JSON 数据") }
                return try bounded(string)
            }
        }
        throw SourceScriptError.unsupported("内置函数 \(namespace).\(name)")
    }
    private func method(_ value: SourceExpressionValue, _ name: String, _ args: [SourceExpressionValue]) throws -> SourceExpressionValue {
        let text = value.string
        let first = args.first ?? .null
        switch name {
        case "trim": return try bounded(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "toLowerCase": return try bounded(text.lowercased())
        case "toUpperCase": return try bounded(text.uppercased())
        case "toString": return try bounded(text)
        case "startsWith": return .bool(text.hasPrefix(first.string))
        case "endsWith": return .bool(text.hasSuffix(first.string))
        case "includes": return .bool(text.contains(first.string))
        case "indexOf": return .number(Double((text as NSString).range(of: first.string).location == NSNotFound ? -1 : (text as NSString).range(of: first.string).location))
        case "substring", "slice", "charAt":
            let string = text as NSString, length = string.length
            var start = args.isEmpty ? 0 : try integer(first)
            var end = args.count > 1 ? try integer(args[1]) : length
            if name == "slice" { start = start < 0 ? length + start : start; end = end < 0 ? length + end : end }
            start = min(length, max(0, start)); end = min(length, max(0, end))
            if name == "charAt" { end = min(length, start + 1) }
            if name == "substring" && end < start { swap(&start, &end) }
            return .text(end < start ? "" : string.substring(with: NSRange(location: start, length: end - start)))
        case "split":
            guard !first.string.isEmpty else { throw SourceScriptError.unsupported("空分隔符 split") }
            let parts = text.components(separatedBy: first.string)
            guard parts.count <= 4096 else { throw SourceScriptError.budgetExceeded }
            return .array(parts.map { .text($0) })
        case "join":
            guard case .array(let values) = value else { throw SourceScriptError.unsupported("join 对象") }
            let separator = args.isEmpty ? "," : first.string
            guard values.reduce(0, { $0 + $1.string.utf16.count }) + separator.utf16.count * values.count <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
            return .text(values.map(\.string).joined(separator: separator))
        case "replace", "replaceAll":
            guard args.count == 2 else { throw SourceScriptError.unsupported("replace 参数") }
            if case .regex(let pattern, let flags) = first { return try regexReplace(text, pattern: pattern, flags: flags, replacement: args[1].string, all: name == "replaceAll") }
            guard !first.string.isEmpty else { throw SourceScriptError.unsupported("空匹配替换") }
            if name == "replaceAll" {
                let maximumReplacements = text.utf16.count / max(1, first.string.utf16.count)
                guard text.utf16.count + maximumReplacements * args[1].string.utf16.count <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
                return try bounded(text.replacingOccurrences(of: first.string, with: args[1].string))
            }
            if let range = text.range(of: first.string) {
                guard text.utf16.count + args[1].string.utf16.count <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
                return .text(text.replacingCharacters(in: range, with: args[1].string))
            }
            return value
        case "match":
            guard case .regex(let pattern, let flags) = first else { throw SourceScriptError.unsupported("match 仅支持正则字面量") }
            let matches = try boundedMatches(text, pattern: pattern, flags: flags, all: flags.contains("g"))
            guard let result = matches.first else { return .null }
            let string = text as NSString
            if flags.contains("g") { return .array(matches.map { .text(string.substring(with: $0.range)) }) }
            return .array((0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                return range.location == NSNotFound ? .null : .text(string.substring(with: range))
            })
        default: throw SourceScriptError.unsupported("方法 \(name)")
        }
    }
    private func boundedMatches(_ text: String, pattern: String, flags: String, all: Bool) throws -> [NSTextCheckingResult] {
        guard pattern.utf8.count <= 512, !pattern.contains("{"), pattern.filter({ $0 == "(" }).count <= 32 else {
            throw SourceScriptError.unsupported("正则复杂度或计数重复")
        }
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { throw SourceScriptError.unsupported("正则表达式") }
        var matches: [NSTextCheckingResult] = []
        var failure: Error?
        // Public Foundation progress callbacks can interrupt a long-running ICU match.
        expression.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: text.utf16.count)) { result, _, stop in
            do { try self.tick() } catch { failure = error; stop.pointee = true; return }
            if let result {
                if matches.count >= 4096 { failure = SourceScriptError.budgetExceeded; stop.pointee = true; return }
                matches.append(result)
                if !all { stop.pointee = true }
            }
        }
        if let failure { throw failure }
        try tick()
        return matches
    }
    private func regexReplace(_ text: String, pattern: String, flags: String, replacement: String, all: Bool) throws -> SourceExpressionValue {
        let matches = try boundedMatches(text, pattern: pattern, flags: flags, all: all || flags.contains("g"))
        guard !matches.isEmpty else { return .text(text) }
        let referenceCount = replacement.filter { $0 == "$" }.count
        var estimatedLength = text.utf16.count
        for match in matches {
            try tick()
            let longestCapture = (0..<match.numberOfRanges).map { match.range(at: $0).length }.max() ?? 0
            estimatedLength += replacement.utf16.count + referenceCount * longestCapture - match.range.length
            guard estimatedLength <= Self.maximumStringLength else { throw SourceScriptError.budgetExceeded }
        }
        let expression = try NSRegularExpression(pattern: pattern)
        var result = text
        for match in matches.reversed() {
            try tick()
            let output = expression.replacementString(for: match, in: text, offset: 0, template: replacement)
            guard result.utf16.count + output.utf16.count <= Self.maximumStringLength,
                  let range = Range(match.range, in: result) else { throw SourceScriptError.budgetExceeded }
            result.replaceSubrange(range, with: output)
        }
        return try bounded(result)
    }
    private func fromJSON(_ object: Any, depth: Int) throws -> SourceExpressionValue {
        try tick(); guard depth < 24 else { throw SourceScriptError.budgetExceeded }
        if let value = object as? String { return try bounded(value) }
        if let value = object as? NSNumber { return CFGetTypeID(value) == CFBooleanGetTypeID() ? .bool(value.boolValue) : .number(value.doubleValue) }
        if let values = object as? [Any] { guard values.count <= 4096 else { throw SourceScriptError.budgetExceeded }; return .array(try values.map { try fromJSON($0, depth: depth + 1) }) }
        if let values = object as? [String: Any] { guard values.count <= 256 else { throw SourceScriptError.budgetExceeded }; return .object(try values.mapValues { try fromJSON($0, depth: depth + 1) }) }
        return .null
    }
    private func toJSON(_ value: SourceExpressionValue, depth: Int) throws -> Any {
        try tick(); guard depth < 24 else { throw SourceScriptError.budgetExceeded }
        switch value {
        case .text(let value): return value
        case .number(let value): guard value.isFinite else { return NSNull() }; return value
        case .bool(let value): return value
        case .array(let values): return try values.map { try toJSON($0, depth: depth + 1) }
        case .object(let values): return try values.mapValues { try toJSON($0, depth: depth + 1) }
        default: return NSNull()
        }
    }
}
