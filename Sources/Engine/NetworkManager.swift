import Foundation
import CoreFoundation

public class NetworkManager {
    public static let shared = NetworkManager()
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9"
        ]
        self.session = URLSession(configuration: config)
    }
    
    private func sanitizeUrlString(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let commaRange = clean.range(of: ",{") {
            clean = String(clean[..<commaRange.lowerBound])
        }
        if let hashRange = clean.range(of: "#") {
            clean = String(clean[..<hashRange.lowerBound])
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func fetchString(from urlString: String, referer: String? = nil) async throws -> (String, URL) {
        let cleanUrlStr = sanitizeUrlString(urlString)
        guard let url = URL(string: cleanUrlStr) ?? URL(string: cleanUrlStr.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if let referer = referer, !referer.isEmpty {
            request.setValue(sanitizeUrlString(referer), forHTTPHeaderField: "Referer")
        }
        
        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        let finalUrl = response.url ?? url
        return (try decodeData(data), finalUrl)
    }
    
    public func executeSearch(source: BookSource, keyword: String) async throws -> (String, URL) {
        guard let rawSearchUrl = source.searchUrl, !rawSearchUrl.isEmpty else {
            throw URLError(.badURL)
        }
        
        // Check if GBK encoding is requested in searchUrl
        let isGBK = rawSearchUrl.lowercased().contains("gbk") || rawSearchUrl.lowercased().contains("gb2312")
        let encodedKey = encodeKeyword(keyword, useGBK: isGBK)
        let cleanBaseUrl = sanitizeUrlString(source.bookSourceUrl)
        
        let replaced: String
        if rawSearchUrl.contains("@js:") || rawSearchUrl.contains("<js>") || rawSearchUrl.contains("java.") {
            replaced = LegadoJSEngine.shared.renderUrlTemplate(
                rawSearchUrl,
                baseUrl: cleanBaseUrl,
                key: keyword,
                page: 1
            )
        } else {
            replaced = rawSearchUrl
                .replacingOccurrences(of: "{{key}}", with: encodedKey)
                .replacingOccurrences(of: "{key}", with: encodedKey)
                .replacingOccurrences(of: "{{page}}", with: "1")
                .replacingOccurrences(of: "{page}", with: "1")
        }
        
        var urlPart = replaced
        var method = "GET"
        var bodyStr: String?
        
        if let commaRange = replaced.range(of: ",{") {
            urlPart = String(replaced[..<commaRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let optPart = "{" + String(replaced[commaRange.upperBound...])
            
            if optPart.lowercased().contains("'post'") || optPart.lowercased().contains("\"post\"") {
                method = "POST"
            }
            
            // Extract body from either JSON or single-quoted dict {'body':'...'}
            if let bodyMatch = extractOptionValue(from: optPart, key: "body") {
                bodyStr = bodyMatch
            }
        }
        
        let fullUrlStr: String
        if urlPart.lowercased().hasPrefix("http") {
            fullUrlStr = urlPart
        } else if let base = URL(string: cleanBaseUrl),
                  let resolved = URL(string: urlPart, relativeTo: base)?.absoluteString {
            fullUrlStr = resolved
        } else {
            fullUrlStr = cleanBaseUrl + (urlPart.hasPrefix("/") ? "" : "/") + urlPart
        }
        
        guard let url = URL(string: fullUrlStr) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(cleanBaseUrl, forHTTPHeaderField: "Referer")
        
        if method == "POST", let bodyStr = bodyStr {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyStr.data(using: .utf8)
        }
        
        let (data, response) = try await session.data(for: request)
        let finalUrl = response.url ?? url
        return (try decodeData(data), finalUrl)
    }
    
    private func extractOptionValue(from optString: String, key: String) -> String? {
        // Try standard JSON first
        let normalized = optString.replacingOccurrences(of: "'", with: "\"")
        if let data = normalized.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let val = dict[key] as? String {
            return val
        }
        // Regex fallback for 'body': '...'
        let pattern = "['\"]\(key)['\"]\\s*:\\s*['\"]([^'\"]+)['\"]"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: optString, range: NSRange(optString.startIndex..., in: optString)),
           let range = Range(match.range(at: 1), in: optString) {
            return String(optString[range])
        }
        return nil
    }
    
    private func encodeKeyword(_ keyword: String, useGBK: Bool) -> String {
        if useGBK {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632)) // GB18030
            if let data = keyword.data(using: String.Encoding(rawValue: nsEnc)) {
                return data.map { String(format: "%%%02X", $0) }.joined()
            }
        }
        return keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
    }
    
    private func decodeData(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        for cfEnc: UInt32 in [0x0632, 0x0631, 0x0630] {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEnc))
            if let text = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
                return text
            }
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw URLError(.cannotDecodeContentData)
    }
}
