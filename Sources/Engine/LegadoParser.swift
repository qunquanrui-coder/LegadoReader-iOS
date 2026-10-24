import Foundation
import SwiftSoup

public class LegadoParser {
    public static let shared = LegadoParser()
    private init() {}
    
    // MARK: - Convert Legado Jsoup Rule to CSS Selector & Attribute
    private func parseLegadoRule(_ rawRule: String) -> (cssSelector: String, attribute: String, regexPattern: String?, regexReplacement: String) {
        // 1. Split regex replacement: rule##pattern##replacement
        let regexParts = rawRule.components(separatedBy: "##")
        var cleanRule = regexParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let regexPattern: String? = regexParts.count > 1 && !regexParts[1].isEmpty ? regexParts[1] : nil
        let regexReplacement: String = regexParts.count > 2 ? regexParts[2] : ""
        
        if cleanRule.hasPrefix("@css:") {
            cleanRule = String(cleanRule.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if cleanRule.hasPrefix("@@") {
            cleanRule = String(cleanRule.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        
        let tokens = cleanRule.components(separatedBy: "@")
        var cssParts: [String] = []
        var finalAttr = "text"
        
        let knownAttributes: Set<String> = ["text", "text()", "textnodes", "ownText", "html", "html()", "href", "src", "content", "data-original", "title"]
        
        for (idx, token) in tokens.enumerated() {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            
            if idx == tokens.count - 1 && knownAttributes.contains(t.lowercased()) {
                finalAttr = t
                continue
            }
            
            cssParts.append(convertTokenToCSS(t))
        }
        
        let cssSelector = cssParts.joined(separator: " ")
        return (cssSelector, finalAttr, regexPattern, regexReplacement)
    }
    
    private func convertTokenToCSS(_ token: String) -> String {
        // Handle Legado syntax like class.bookbox.0, id.list, tag.a.0, children
        if token == "children" {
            return "> *"
        }
        
        var working = token
        // Strip trailing index like .0 or .-1 or !0
        if let bangIdx = working.range(of: "!") {
            working = String(working[..<bangIdx.lowerBound])
        }
        
        let dotParts = working.components(separatedBy: ".")
        if dotParts.count >= 2 {
            let prefix = dotParts[0]
            if prefix == "class" {
                let className = dotParts[1].replacingOccurrences(of: " ", with: ".")
                return ".\(className)"
            } else if prefix == "id" {
                return "#\(dotParts[1])"
            } else if prefix == "tag" {
                return dotParts[1]
            }
        }
        return working
    }
    
    // MARK: - Rule Extraction Helper
    public func extractValue(from element: Element, rule: String?, baseUrl: URL) -> String? {
        guard let rule = rule, !rule.isEmpty else { return nil }
        
        // Support fallback alternatives separated by "||"
        let alternatives = rule.components(separatedBy: "||")
        for alt in alternatives {
            if let val = extractSingleRule(from: element, rule: alt, baseUrl: baseUrl), !val.isEmpty {
                return val
            }
        }
        return nil
    }
    
    private func extractSingleRule(from element: Element, rule: String, baseUrl: URL) -> String? {
        let parsed = parseLegadoRule(rule)
        
        do {
            let targetElement: Element
            if parsed.cssSelector.isEmpty {
                targetElement = element
            } else {
                guard let found = try element.select(parsed.cssSelector).first() else {
                    return nil
                }
                targetElement = found
            }
            
            var result: String = ""
            switch parsed.attribute.lowercased() {
            case "text", "text()", "textnodes", "owntext":
                result = try targetElement.text()
            case "html", "html()":
                result = try targetElement.html()
            default:
                result = try targetElement.attr(parsed.attribute)
            }
            
            // Apply regex replacement if present
            if let pattern = parsed.regexPattern {
                result = result.replacingOccurrences(of: pattern, with: parsed.regexReplacement, options: .regularExpression)
            }
            
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Auto resolve relative URLs for href, src, content
            let attrLower = parsed.attribute.lowercased()
            if attrLower == "href" || attrLower == "src" || attrLower == "data-original" || result.hasPrefix("/") {
                if !result.isEmpty, !result.lowercased().hasPrefix("http") {
                    if let resolved = URL(string: result, relativeTo: baseUrl)?.absoluteString {
                        return resolved
                    }
                }
            }
            
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }
    
    private func selectElements(in doc: Document, rule: String) -> Elements? {
        let alternatives = rule.components(separatedBy: "||")
        for alt in alternatives {
            var cleanAlt = alt.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanAlt.hasPrefix("-") || cleanAlt.hasPrefix("+") {
                cleanAlt = String(cleanAlt.dropFirst())
            }
            let parsed = parseLegadoRule(cleanAlt)
            if !parsed.cssSelector.isEmpty,
               let els = try? doc.select(parsed.cssSelector),
               !els.isEmpty() {
                return els
            }
        }
        return nil
    }
    
    // MARK: - Search Parsing
    public func parseSearch(html: String, baseUrl: URL, source: BookSource) throws -> [Book] {
        let doc = try SwiftSoup.parse(html, baseUrl.absoluteString)
        guard let ruleSearch = source.ruleSearch,
              let listRule = ruleSearch.bookList,
              !listRule.isEmpty,
              let elements = selectElements(in: doc, rule: listRule) else {
            return []
        }
        
        var books: [Book] = []
        for el in elements {
            let name = extractValue(from: el, rule: ruleSearch.name, baseUrl: baseUrl) ?? ""
            if name.isEmpty { continue }
            
            let author = extractValue(from: el, rule: ruleSearch.author, baseUrl: baseUrl) ?? "佚名"
            let intro = extractValue(from: el, rule: ruleSearch.intro, baseUrl: baseUrl)
            let coverUrl = extractValue(from: el, rule: ruleSearch.coverUrl, baseUrl: baseUrl)
            let lastChapter = extractValue(from: el, rule: ruleSearch.lastChapter, baseUrl: baseUrl)
            let bookUrl = extractValue(from: el, rule: ruleSearch.bookUrl ?? "a@href", baseUrl: baseUrl) ?? baseUrl.absoluteString
            
            let book = Book(
                title: name,
                author: author,
                coverUrl: coverUrl,
                intro: intro,
                latestChapter: lastChapter,
                sourceUrl: source.bookSourceUrl,
                sourceName: source.bookSourceName,
                bookUrl: bookUrl
            )
            books.append(book)
        }
        
        return books
    }
    
    // MARK: - TOC (Table of Contents) Parsing
    public func parseToc(html: String, baseUrl: URL, source: BookSource) throws -> [Chapter] {
        let doc = try SwiftSoup.parse(html, baseUrl.absoluteString)
        let listRule = source.ruleToc?.chapterList ?? "#list dd a||.listmain dd a||#chapterlist a"
        guard let elements = selectElements(in: doc, rule: listRule) else {
            return []
        }
        
        var chapters: [Chapter] = []
        var seenUrls = Set<String>()
        var index = 0
        
        for el in elements {
            let title = extractValue(from: el, rule: source.ruleToc?.chapterName ?? "text", baseUrl: baseUrl) ?? ""
            guard let url = extractValue(from: el, rule: source.ruleToc?.chapterUrl ?? "href", baseUrl: baseUrl) else {
                continue
            }
            
            if !title.isEmpty && !url.isEmpty && !seenUrls.contains(url) {
                seenUrls.insert(url)
                chapters.append(Chapter(index: index, title: title, url: url))
                index += 1
            }
        }
        
        return chapters
    }
    
    // MARK: - Chapter Content Parsing
    public func parseContent(html: String, baseUrl: URL, source: BookSource) throws -> String {
        let doc = try SwiftSoup.parse(html, baseUrl.absoluteString)
        let ruleContent = source.ruleContent?.content ?? "#content@html||#chaptercontent@html||.read-content@html"
        
        let alternatives = ruleContent.components(separatedBy: "||")
        for alt in alternatives {
            let parsed = parseLegadoRule(alt)
            if !parsed.cssSelector.isEmpty,
               let contentEl = try? doc.select(parsed.cssSelector).first() {
                var raw = (try? contentEl.html()) ?? ""
                if let pattern = parsed.regexPattern {
                    raw = raw.replacingOccurrences(of: pattern, with: parsed.regexReplacement, options: .regularExpression)
                }
                let cleaned = cleanNovelText(raw)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        
        // Fallback: try common novel content selectors
        for fallback in ["#content", "#chaptercontent", ".read-content", "#booktxt", ".content", "#nr1"] {
            if let found = try? doc.select(fallback).first() {
                let cleaned = cleanNovelText((try? found.html()) ?? "")
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        
        return "未能解析章节正文，请检查书源规则或点击右上角刷新重试。"
    }
    
    // MARK: - Clean HTML to Reader Prose
    private func cleanNovelText(_ rawHtml: String) -> String {
        var text = rawHtml
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<p[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#160;", with: " ")
        
        let lines = text.components(separatedBy: .newlines)
        let formattedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "　　" + $0 }
        
        return formattedLines.joined(separator: "\n\n")
    }
}
