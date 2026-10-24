import Foundation
import CoreFoundation

public class NetworkManager {
    public static let shared = NetworkManager()
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        self.session = URLSession(configuration: config)
    }
    
    public func fetchString(from urlString: String, referer: String? = nil) async throws -> (String, URL) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        if let referer = referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        
        let (data, response) = try await session.data(for: request)
        let finalUrl = response.url ?? url
        return (try decodeData(data), finalUrl)
    }
    
    public func executeSearch(source: BookSource, keyword: String) async throws -> (String, URL) {
        guard let rawSearchUrl = source.searchUrl, !rawSearchUrl.isEmpty else {
            throw URLError(.badURL)
        }
        
        let encodedKey = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let replaced = rawSearchUrl
            .replacingOccurrences(of: "{{key}}", with: encodedKey)
            .replacingOccurrences(of: "{key}", with: encodedKey)
            .replacingOccurrences(of: "searchKey", with: encodedKey)
        
        // Check if Legado searchUrl has ",{...}" options
        var urlPart = replaced
        var method = "GET"
        var bodyStr: String?
        
        if let commaRange = replaced.range(of: ",{") {
            urlPart = String(replaced[..<commaRange.lowerBound])
            let jsonPart = "{" + String(replaced[commaRange.upperBound...])
            if let jsonData = jsonPart.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let m = dict["method"] as? String {
                    method = m.uppercased()
                }
                if let b = dict["body"] as? String {
                    bodyStr = b
                }
            }
        }
        
        // Resolve relative searchUrl against bookSourceUrl
        let fullUrlStr: String
        if urlPart.lowercased().hasPrefix("http") {
            fullUrlStr = urlPart
        } else if let base = URL(string: source.bookSourceUrl),
                  let resolved = URL(string: urlPart, relativeTo: base)?.absoluteString {
            fullUrlStr = resolved
        } else {
            fullUrlStr = source.bookSourceUrl + (urlPart.hasPrefix("/") ? "" : "/") + urlPart
        }
        
        guard let url = URL(string: fullUrlStr) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(source.bookSourceUrl, forHTTPHeaderField: "Referer")
        
        if method == "POST", let bodyStr = bodyStr {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyStr.data(using: .utf8)
        }
        
        let (data, response) = try await session.data(for: request)
        let finalUrl = response.url ?? url
        return (try decodeData(data), finalUrl)
    }
    
    private func decodeData(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        // GB18030 (0x0632) & GBK (0x0631)
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
