import Foundation
import JavaScriptCore
import CryptoKit

/// Native JavaScriptCore execution engine for Legado `@js:`, `<js>...</js>`, and `{{...}}` book source rules.
public final class LegadoJSEngine {
    public static let shared = LegadoJSEngine()
    private let lock = NSLock()
    private var variables: [String: String] = [:]
    
    private init() {}
    
    /// Evaluates a Legado JavaScript snippet with `result`, `baseUrl`, `key`, `page`, and `java.*` helpers injected.
    public func evaluate(
        script: String,
        result: String? = nil,
        baseUrl: String = "",
        key: String = "",
        page: Int = 1
    ) -> String? {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let ctx = JSContext() else { return result }
        ctx.exceptionHandler = { _, _ in }
        
        ctx.setObject(result ?? "", forKeyedSubscript: "result" as NSString)
        ctx.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        ctx.setObject(baseUrl, forKeyedSubscript: "sourceUrl" as NSString)
        ctx.setObject(key, forKeyedSubscript: "key" as NSString)
        ctx.setObject(page, forKeyedSubscript: "page" as NSString)
        
        // Provide standard Legado `java` helper functions via native closures
        let encodeURIBlock: @convention(block) (String, JSValue?) -> String = { str, encVal in
            let encName = (encVal?.isUndefined == false && encVal?.isNull == false) ? (encVal?.toString() ?? "") : "utf-8"
            if encName.lowercased().contains("gb") {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
                if let data = str.data(using: String.Encoding(rawValue: nsEnc)) {
                    return data.map { String(format: "%%%02X", $0) }.joined()
                }
            }
            return str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str
        }
        ctx.setObject(encodeURIBlock, forKeyedSubscript: "__legado_encodeURI" as NSString)
        
        let base64EncodeBlock: @convention(block) (String) -> String = { str in
            Data(str.utf8).base64EncodedString()
        }
        ctx.setObject(base64EncodeBlock, forKeyedSubscript: "__legado_base64Encode" as NSString)
        
        let base64DecodeBlock: @convention(block) (String) -> String = { str in
            guard let data = Data(base64Encoded: str),
                  let decoded = String(data: data, encoding: .utf8) else { return "" }
            return decoded
        }
        ctx.setObject(base64DecodeBlock, forKeyedSubscript: "__legado_base64Decode" as NSString)
        
        let md5Block: @convention(block) (String) -> String = { str in
            let digest = Insecure.MD5.hash(data: Data(str.utf8))
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        ctx.setObject(md5Block, forKeyedSubscript: "__legado_md5" as NSString)
        
        let putVarBlock: @convention(block) (String, String) -> String = { [weak self] k, v in
            self?.variables[k] = v
            return v
        }
        ctx.setObject(putVarBlock, forKeyedSubscript: "__legado_put" as NSString)
        
        let getVarBlock: @convention(block) (String) -> String = { [weak self] k in
            self?.variables[k] ?? ""
        }
        ctx.setObject(getVarBlock, forKeyedSubscript: "__legado_get" as NSString)
        
        ctx.evaluateScript("""
        var java = {
            encodeURI: function(s, enc) { return __legado_encodeURI(String(s || ''), enc); },
            base64Encode: function(s) { return __legado_base64Encode(String(s || '')); },
            base64Decode: function(s) { return __legado_base64Decode(String(s || '')); },
            md5Encode: function(s) { return __legado_md5(String(s || '')); },
            md5Encode16: function(s) { return __legado_md5(String(s || '')).substring(8, 24); },
            put: function(k, v) { return __legado_put(String(k), String(v || '')); },
            get: function(k) { return __legado_get(String(k)); },
            timeFormat: function(ts) { return new Date(Number(ts) || Date.now()).toISOString(); },
            t2s: function(s) { return String(s || ''); },
            s2t: function(s) { return String(s || ''); }
        };
        var cookie = { getKey: function() { return ''; } };
        var cache = { get: function(k) { return __legado_get(String(k)); }, put: function(k, v) { return __legado_put(String(k), String(v)); } };
        """)
        
        guard let val = ctx.evaluateScript(trimmed), !val.isUndefined, !val.isNull else {
            return nil
        }
        let str = val.toString() ?? ""
        return str == "undefined" || str == "null" ? nil : str
    }
    
    /// Splits a Legado rule into `(selectorPart, [jsSnippets])` if it contains `@js:` or `<js>...</js>`.
    public func splitSelectorAndJS(_ rawRule: String) -> (selector: String, scripts: [String]) {
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
