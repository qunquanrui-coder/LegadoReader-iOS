import Foundation
import SwiftSoup

public class LegadoParser {
    public static let shared = LegadoParser()
    private init() {}
    
    private let knownAttributes: Set<String> = [
        "text", "text()", "textnodes", "owntext", "html", "html()",
        "href", "src", "content", "data-original", "data-src", "title", "value", "alt"
    ]
    
    // MARK: - Step-by-Step Legado Rule Selector
    public func stepSelect(from roots: [Element], chainRule: String) -> [Element] {
        var clean = chainRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return roots }
        
        if clean.hasPrefix("@css:") {
            clean = String(clean.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if clean.hasPrefix("@@") {
            clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if clean.hasPrefix("-") || clean.hasPrefix("+") {
            clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        
        let tokens = clean.components(separatedBy: "@")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var current = roots
        
        for rawToken in tokens {
            var token = rawToken
            var pickIndex: Int? = nil
            var excludeIndex: Int? = nil
            var reverseList = false
            
            // Check reverse slice like [-1:0]
            if token.contains("[-1:0]") {
                reverseList = true
            }
            if let bracketRange = token.range(of: "[") {
                let inside = String(token[bracketRange.lowerBound...])
                if inside.contains(":") {
                    token = String(token[..<bracketRange.lowerBound])
                }
            }
            
            // Check exclude index like !0 or .-1 or !-1
            if let bangRange = token.range(of: "!") {
                let exclStr = String(token[bangRange.upperBound...]).replacingOccurrences(of: ".", with: "")
                excludeIndex = Int(exclStr)
                token = String(token[..<bangRange.lowerBound])
                if token.hasSuffix(".") {
                    token = String(token.dropLast())
                }
            }
            
            // Check trailing index like .0, .1, .-1
            let dotParts = token.components(separatedBy: ".")
            if dotParts.count >= 2, let idx = Int(dotParts.last!) {
                pickIndex = idx
                token = dotParts.dropLast().joined(separator: ".")
            }
            
            let css = convertSingleTokenToCSS(token)
            var nextElements: [Element] = []
            
            for el in current {
                if css.isEmpty {
                    nextElements.append(el)
                } else if let found = try? el.select(css) {
                    var arr = found.array()
                    // In Jsoup/SwiftSoup, el.select(css) includes `el` itself at index 0 if `el` matches `css`.
                    // Remove self if searching inside a container for child elements of same type.
                    if arr.count > 1 && arr.first === el {
                        arr.removeFirst()
                    }
                    nextElements.append(contentsOf: arr)
                }
            }
            
            if reverseList {
                nextElements.reverse()
            }
            
            if let excl = excludeIndex, !nextElements.isEmpty {
                let realIdx = excl >= 0 ? excl : (nextElements.count + excl)
                if realIdx >= 0 && realIdx < nextElements.count {
                    nextElements.remove(at: realIdx)
                }
            }
            
            if let pick = pickIndex {
                let realIdx = pick >= 0 ? pick : (nextElements.count + pick)
                if realIdx >= 0 && realIdx < nextElements.count {
                    nextElements = [nextElements[realIdx]]
                } else {
                    nextElements = []
                }
            }
            
            current = nextElements
            if current.isEmpty {
                break
            }
        }
        
        return current
    }
    
    private func convertSingleTokenToCSS(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed == "children" { return "> *" }
        
        // Handle XPath meta tags commonly used in XIU2: //meta[@property='og:novel:book_name']
        if trimmed.hasPrefix("//meta[") {
            if let propRange = trimmed.range(of: "@property='"),
               let endQuote = trimmed[propRange.upperBound...].firstIndex(of: "'") {
                let propName = String(trimmed[propRange.upperBound..<endQuote])
                return "meta[property=\"\(propName)\"]"
            }
        }
        
        let parts = trimmed.components(separatedBy: ".")
        if parts.count >= 2 {
            let prefix = parts[0]
            let rest = parts.dropFirst().joined(separator: ".")
            switch prefix {
            case "class":
                let classes = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: ".")
                return ".\(classes)"
            case "id":
                return "#\(rest)"
            case "tag":
                return rest
            case "text":
                return "a:contains(\(rest))"
            default:
                break
            }
        }
        return trimmed
    }
    
    // MARK: - Extract String Value from Element
    public func extractValue(from element: Element, rule: String?, baseUrl: URL) -> String? {
        guard let rule = rule, !rule.isEmpty else { return nil }
        
        // Handle && (combine multiple rules) or || (fallback alternatives)
        let orAlternatives = rule.components(separatedBy: "||")
        for alt in orAlternatives {
            let andParts = alt.components(separatedBy: "&&")
            var combined: [String] = []
            for part in andParts {
                if let val = extractSingleRule(from: element, rawRule: part, baseUrl: baseUrl), !val.isEmpty {
                    combined.append(val)
                }
            }
            if !combined.isEmpty {
                return combined.joined(separator: " · ")
            }
        }
        return nil
    }
    
    private func extractSingleRule(from element: Element, rawRule: String, baseUrl: URL) -> String? {
        let (cleanRaw, jsScripts) = LegadoJSEngine.shared.splitSelectorAndJS(rawRule)
        
        // Pure @js: or <js> rule with no preceding DOM selector
        if cleanRaw.isEmpty && !jsScripts.isEmpty {
            var currentVal: String? = (try? element.html()) ?? ""
            for script in jsScripts {
                currentVal = LegadoJSEngine.shared.evaluate(
                    script: script,
                    result: currentVal,
                    baseUrl: baseUrl.absoluteString
                )
            }
            guard var jsRes = currentVal?.trimmingCharacters(in: .whitespacesAndNewlines), !jsRes.isEmpty else {
                return nil
            }
            if jsRes.hasPrefix("/") && !jsRes.lowercased().hasPrefix("http") {
                if let resolved = URL(string: jsRes, relativeTo: baseUrl)?.absoluteString {
                    jsRes = resolved
                }
            }
            return jsRes
        }
        
        let regexParts = cleanRaw.components(separatedBy: "##")
        var selectorPart = regexParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let regexPattern: String? = regexParts.count > 1 && !regexParts[1].isEmpty ? regexParts[1] : nil
        let regexReplacement: String = regexParts.count > 2 ? regexParts[2] : ""
        
        // Handle XPath attribute suffix like /@content or /@href or /text()
        var attribute = "text"
        if selectorPart.hasSuffix("/@content") {
            selectorPart = String(selectorPart.dropLast(9))
            attribute = "content"
        } else if selectorPart.hasSuffix("/@href") {
            selectorPart = String(selectorPart.dropLast(6))
            attribute = "href"
        } else if selectorPart.hasSuffix("/text()") {
            selectorPart = String(selectorPart.dropLast(7))
            attribute = "text"
        }
        
        var tokens = selectorPart.components(separatedBy: "@")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if let last = tokens.last, knownAttributes.contains(last.lowercased()) {
            attribute = last.lowercased()
            tokens.removeLast()
        }
        
        let targetElements: [Element]
        if tokens.isEmpty {
            targetElements = [element]
        } else {
            targetElements = stepSelect(from: [element], chainRule: tokens.joined(separator: "@"))
        }
        
        guard !targetElements.isEmpty else { return nil }
        
        let isUrlAttr = (attribute == "href" || attribute == "src" || attribute == "data-original" || attribute == "data-src")
        var extractedValues: [String] = []
        
        for el in targetElements {
            var val: String?
            switch attribute {
            case "text", "text()", "owntext":
                val = try? el.text()
            case "textnodes":
                // Preserve line breaks from <br> and <p> tags when extracting textNodes
                if let rawHtml = try? el.html() {
                    let withNewlines = rawHtml
                        .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
                        .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
                        .replacingOccurrences(of: "<p[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    val = withNewlines
                } else {
                    val = try? el.text()
                }
            case "html", "html()":
                val = try? el.html()
            default:
                val = try? el.attr(attribute)
            }
            if let v = val?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                extractedValues.append(v)
                if isUrlAttr { break } // Only need first URL for href/src
            }
        }
        
        guard !extractedValues.isEmpty else { return nil }
        var result = extractedValues.joined(separator: "\n")
        
        if let pattern = regexPattern {
            result = result.replacingOccurrences(of: pattern, with: regexReplacement, options: .regularExpression)
        }
        
        // Pipe extracted selector result through any trailing <js>...</js> or @js: scripts
        for script in jsScripts {
            if let jsOut = LegadoJSEngine.shared.evaluate(
                script: script,
                result: result,
                baseUrl: baseUrl.absoluteString
            ) {
                result = jsOut
            }
        }
        
        // Strip Legado trailing options like ,{'webView':true}
        if isUrlAttr, let commaOpt = result.range(of: ",{") {
            result = String(result[..<commaOpt.lowerBound])
        }
        
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return nil }
        
        if isUrlAttr || result.hasPrefix("/") {
            if !result.lowercased().hasPrefix("http") {
                if let resolved = URL(string: result, relativeTo: baseUrl)?.absoluteString {
                    return resolved
                }
            }
        }
        
        return result
    }
    
    // MARK: - Search Parsing
    public func parseSearch(html: String, baseUrl: URL, source: BookSource) throws -> [Book] {
        let doc = try SwiftSoup.parse(html, baseUrl.absoluteString)
        guard let ruleSearch = source.ruleSearch,
              let listRule = ruleSearch.bookList,
              !listRule.isEmpty else {
            return []
        }
        
        var elements: [Element] = []
        for alt in listRule.components(separatedBy: "||") {
            let found = stepSelect(from: [doc], chainRule: alt)
            if !found.isEmpty {
                elements = found
                break
            }
        }
        
        var books: [Book] = []
        let cleanSourceUrl = source.bookSourceUrl.components(separatedBy: "#").first ?? source.bookSourceUrl
        
        for el in elements {
            let name = extractValue(from: el, rule: ruleSearch.name, baseUrl: baseUrl) ?? ""
            if name.isEmpty { continue }
            
            let author = (extractValue(from: el, rule: ruleSearch.author, baseUrl: baseUrl) ?? "佚名")
                .replacingOccurrences(of: "作者：", with: "")
                .replacingOccurrences(of: "作者:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let intro = extractValue(from: el, rule: ruleSearch.intro, baseUrl: baseUrl)
            let coverUrl = extractValue(from: el, rule: ruleSearch.coverUrl, baseUrl: baseUrl)
            let lastChapter = extractValue(from: el, rule: ruleSearch.lastChapter, baseUrl: baseUrl)
            
            guard let bookUrl = extractValue(from: el, rule: ruleSearch.bookUrl ?? "tag.a.0@href||a@href", baseUrl: baseUrl) else {
                continue
            }
            
            let book = Book(
                title: name,
                author: author.isEmpty ? "佚名" : author,
                coverUrl: coverUrl,
                intro: intro,
                latestChapter: lastChapter,
                sourceUrl: source.bookSourceUrl,
                sourceName: source.bookSourceName,
                bookUrl: bookUrl.hasPrefix("http") ? bookUrl : (URL(string: bookUrl, relativeTo: URL(string: cleanSourceUrl))?.absoluteString ?? bookUrl)
            )
            books.append(book)
        }
        
        return books
    }
    
    // MARK: - Resolve Separate TOC URL if Present on Book Info Page
    public func resolveTocUrl(html: String, baseUrl: URL, source: BookSource) -> String? {
        guard let tocRule = source.ruleBookInfo?.tocUrl, !tocRule.isEmpty else {
            return nil
        }
        if tocRule.contains("@js:") || tocRule.contains("<js>") {
            let (selPart, scripts) = LegadoJSEngine.shared.splitSelectorAndJS(tocRule)
            var current: String? = baseUrl.absoluteString
            if !selPart.isEmpty, let doc = try? SwiftSoup.parse(html, baseUrl.absoluteString) {
                current = extractValue(from: doc, rule: selPart, baseUrl: baseUrl) ?? baseUrl.absoluteString
            }
            for script in scripts {
                if let out = LegadoJSEngine.shared.evaluate(script: script, result: current, baseUrl: baseUrl.absoluteString), !out.isEmpty {
                    current = out
                }
            }
            if let resolved = current, !resolved.isEmpty {
                if resolved.lowercased().hasPrefix("http") {
                    return resolved
                } else if let abs = URL(string: resolved, relativeTo: baseUrl)?.absoluteString {
                    return abs
                }
            }
            if tocRule.contains("replace('/txt','')") {
                return baseUrl.absoluteString
                    .replacingOccurrences(of: "/txt", with: "")
                    .replacingOccurrences(of: ".htm", with: "/")
            }
            return nil
        }
        guard let doc = try? SwiftSoup.parse(html, baseUrl.absoluteString) else { return nil }
        return extractValue(from: doc, rule: tocRule, baseUrl: baseUrl)
    }
    
    // MARK: - High-Level Fetch & Parse TOC (Handles Separate TOC URL, Pagination + Fallbacks)
    /// Outcome of a TOC fetch. `complete` is false when the pagination walk hit a page
    /// limit, a repeated page, a URL loop or a network error before it ran out of
    /// "next page" links. Callers may cache a partial TOC, but must not label it complete.
    public struct TocLoadResult {
        public let chapters: [Chapter]
        public let complete: Bool
        public let pagesFetched: Int
        public let lastErrorDescription: String?
        public init(chapters: [Chapter], complete: Bool, pagesFetched: Int, lastErrorDescription: String? = nil) {
            self.chapters = chapters
            self.complete = complete
            self.pagesFetched = pagesFetched
            self.lastErrorDescription = lastErrorDescription
        }
    }

    public typealias TocFetchPage = (String, String?) async throws -> (String, URL)

    /// Fetches and parses the whole catalogue, following `ruleToc.nextTocUrl` (or a
    /// best-effort "下一页" / rel=next link) across paginated catalogues, then re-indexes
    /// every chapter so indices always equal positions in the returned array.
    public func fetchToc(
        bookUrl: String,
        source: BookSource,
        maxPages: Int = 50,
        fetchPage: @escaping TocFetchPage = {
            try await NetworkManager.shared.fetchString(from: $0, referer: $1)
        }
    ) async throws -> TocLoadResult {
        let pageLimit = max(1, maxPages)
        let (bookHtml, finalBookUrl) = try await fetchPage(bookUrl, source.bookSourceUrl)

        var currentHtml = bookHtml
        var currentURL = finalBookUrl

        // 1. Prefer a separate TOC page when the book-info rule points at one. When that page is
        //    declared but cannot be fetched/parsed, the book-info fallback below is only a preview
        //    (often "latest 5 chapters"), so the whole result must stay incomplete.
        var separateTocUnavailable = false
        if let separateTocUrl = resolveTocUrl(html: bookHtml, baseUrl: finalBookUrl, source: source),
           separateTocUrl != finalBookUrl.absoluteString {
            var usedSeparateToc = false
            if let (tocHtml, finalTocUrl) = try? await fetchPage(separateTocUrl, finalBookUrl.absoluteString) {
                let provisional = (try? parseToc(html: tocHtml, baseUrl: finalTocUrl, source: source)) ?? []
                if provisional.count >= 3 {
                    currentHtml = tocHtml
                    currentURL = finalTocUrl
                    usedSeparateToc = true
                }
            }
            separateTocUnavailable = !usedSeparateToc
        }

        var collected: [Chapter] = []
        var seenChapterURLs = Set<String>()
        var visitedTocPages = Set<String>()
        var pageCount = 0
        var complete = true
        var lastError: String?

        while true {
            try Task.checkCancellation()
            let pageKey = canonicalURLKey(currentURL.absoluteString)
            guard visitedTocPages.insert(pageKey).inserted else {
                complete = false
                break
            }

            let parsed: [Chapter]
            do {
                parsed = try parseToc(html: currentHtml, baseUrl: currentURL, source: source)
            } catch {
                if pageCount == 0 { throw error }
                complete = false
                lastError = error.localizedDescription
                break
            }

            var addedOnThisPage = 0
            for chapter in parsed {
                let chapterKey = canonicalURLKey(chapter.url)
                guard !chapterKey.isEmpty, !seenChapterURLs.contains(chapterKey) else { continue }
                seenChapterURLs.insert(chapterKey)
                collected.append(chapter)
                addedOnThisPage += 1
            }
            pageCount += 1

            if pageCount == 1 && collected.isEmpty {
                return TocLoadResult(chapters: [], complete: false, pagesFetched: pageCount)
            }
            // A later page that adds nothing new is a repeated/blank page: stop instead of looping.
            if pageCount > 1 && addedOnThisPage == 0 {
                complete = false
                break
            }
            if pageCount >= pageLimit {
                complete = false
                break
            }

            guard let nextURLString = resolveNextTocURL(
                html: currentHtml,
                baseUrl: currentURL,
                source: source,
                allowLabelHeuristic: collected.count >= 5
            ), let nextURL = URL(string: nextURLString) else { break }

            let nextKey = canonicalURLKey(nextURL.absoluteString)
            if nextKey.isEmpty || nextKey == pageKey || visitedTocPages.contains(nextKey) {
                complete = false
                break
            }
            // Never treat an already-collected chapter link as another catalogue page.
            if seenChapterURLs.contains(nextKey) { break }

            do {
                let (nextHtml, finalNextURL) = try await fetchPage(nextURL.absoluteString, currentURL.absoluteString)
                currentHtml = nextHtml
                currentURL = finalNextURL
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                complete = false
                lastError = error.localizedDescription
                break
            }
        }

        // The source declares a dedicated TOC page but it failed: whatever the book-info page
        // yielded is a preview only, so this catalogue can never be labelled complete.
        if separateTocUnavailable { complete = false }

        let chapters = collected.enumerated().map { offset, chapter in
            Chapter(index: offset, title: chapter.title, url: chapter.url)
        }
        return TocLoadResult(chapters: chapters, complete: complete, pagesFetched: pageCount,
                             lastErrorDescription: lastError)
    }

    /// Backwards-compatible entry point for callers that only need the chapter list.
    public func fetchAndParseToc(bookUrl: String, source: BookSource) async throws -> [Chapter] {
        let result = try await fetchToc(bookUrl: bookUrl, source: source)
        return result.chapters
    }

    // MARK: - TOC Pagination Helpers
    private func resolveNextTocURL(html: String, baseUrl: URL, source: BookSource,
                                   allowLabelHeuristic: Bool) -> String? {
        guard let doc = try? SwiftSoup.parse(html, baseUrl.absoluteString) else { return nil }

        // 1. Explicit Legado `nextTocUrl` rule (selector / @js / text.下一页 ...)
        if let rule = source.ruleToc?.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty,
           let raw = extractValue(from: doc, rule: rule, baseUrl: baseUrl),
           let resolved = resolveURLString(raw, base: baseUrl) {
            return resolved
        }

        // 2. rel="next" links
        for selector in ["a[rel=next]", "link[rel=next]"] {
            guard let elements = try? doc.select(selector).array(), !elements.isEmpty else { continue }
            for element in elements {
                if let href = try? element.attr("href"), let resolved = resolveURLString(href, base: baseUrl) {
                    return resolved
                }
            }
        }

        // 3. "下一页 / Next" labels, but only inside a pagination-looking container and
        //    only once the current page already looks like a real catalogue (avoids
        //    following unrelated page links on a book detail page).
        guard allowLabelHeuristic else { return nil }
        let nextLabels: Set<String> = ["下一页", "下页", "下一頁", "下頁", "next", "nextpage", "next page", "»", ">>", ">"]
        if let anchors = try? doc.select("a[href]").array() {
            for anchor in anchors {
                let text = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
                guard nextLabels.contains(compact), isInsidePaginationContainer(anchor) else { continue }
                if let href = try? anchor.attr("href"), let resolved = resolveURLString(href, base: baseUrl) {
                    return resolved
                }
            }
        }
        return nil
    }

    private func isInsidePaginationContainer(_ element: Element) -> Bool {
        var node: Element? = element
        var depth = 0
        while let current = node, depth < 4 {
            let className = ((try? current.className()) ?? "").lowercased()
            let identifier = ((try? current.attr("id")) ?? "").lowercased()
            if className.contains("pag") || className.contains("page")
                || identifier.contains("pag") || identifier.contains("page") {
                return true
            }
            node = current.parent()
            depth += 1
        }
        return false
    }

    private func resolveURLString(_ raw: String, base: URL) -> String? {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let commaOption = clean.range(of: ",{") { clean = String(clean[..<commaOption.lowerBound]) }
        guard !clean.isEmpty, !clean.lowercased().hasPrefix("javascript"), !clean.hasPrefix("#") else { return nil }
        if clean.lowercased().hasPrefix("http://") || clean.lowercased().hasPrefix("https://") {
            if let hash = clean.range(of: "#") { clean = String(clean[..<hash.lowerBound]) }
            return clean
        }
        return URL(string: clean, relativeTo: base)?.absoluteString
    }

    /// Normalises a URL so repeated pages / chapters are detected even if the site mixes
    /// fragments, default ports or letter case in the host name.
    private func canonicalURLKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return trimmed.lowercased() }
        components.fragment = nil
        if let scheme = components.scheme { components.scheme = scheme.lowercased() }
        if let host = components.host { components.host = host.lowercased() }
        if (components.scheme == "http" && components.port == 80)
            || (components.scheme == "https" && components.port == 443) {
            components.port = nil
        }
        var key = components.url?.absoluteString ?? trimmed
        if key.hasSuffix("/"), key.count > 1 { key = String(key.dropLast()) }
        return key
    }

    // MARK: - TOC (Table of Contents) Parsing + Smart Fallback
    public func parseToc(html: String, baseUrl: URL, source: BookSource) throws -> [Chapter] {
        let doc = try SwiftSoup.parse(html, baseUrl.absoluteString)
        var chapters: [Chapter] = []
        
        // 1. Try explicit ruleToc from bookSource
        if let listRule = source.ruleToc?.chapterList, !listRule.isEmpty {
            var elements: [Element] = []
            for alt in listRule.components(separatedBy: "||") {
                let found = stepSelect(from: [doc], chainRule: alt)
                if !found.isEmpty {
                    elements = found
                    break
                }
            }
            
            let nameRule = source.ruleToc?.chapterName ?? "text"
            let urlRule = source.ruleToc?.chapterUrl ?? "href"
            chapters = extractChapters(from: elements, nameRule: nameRule, urlRule: urlRule, baseUrl: baseUrl)
        }
        
        // 2. Smart Auto-Discovery Fallback if ruleToc yielded too few chapters
        if chapters.count < 3 {
            let fallbackSelectors = [
                "#list dd a", ".listmain dd a", "#chapterlist a", "#ul_all_chapters li a",
                "#list-chapterAll a", ".section-list.-1 a", ".book_list a", ".catalog a",
                ".chapter-list a", ".list_xm.-1 a", ".directoryArea.-1 a", "dl dd a", ".list a"
            ]
            for sel in fallbackSelectors {
                let els = stepSelect(from: [doc], chainRule: sel)
                if els.count >= 5 {
                    let candidate = extractChapters(from: els, nameRule: "text", urlRule: "href", baseUrl: baseUrl)
                    if candidate.count > chapters.count {
                        chapters = candidate
                        break
                    }
                }
            }
        }
        
        // 3. Deep heuristic: scan all <a> tags on page that look like novel chapters
        if chapters.isEmpty, let allLinks = try? doc.select("a[href]").array() {
            var heuristic: [Chapter] = []
            var seen = Set<String>()
            var idx = 0
            for a in allLinks {
                guard let title = try? a.text().trimmingCharacters(in: .whitespacesAndNewlines),
                      let href = try? a.attr("href").trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty, !href.isEmpty,
                      !href.hasPrefix("javascript"), !href.hasPrefix("#") else { continue }
                
                let looksLikeChapter = title.contains("第") && (title.contains("章") || title.contains("节") || title.contains("回"))
                    || title.range(of: "^\\d+[、. 　]", options: .regularExpression) != nil
                if looksLikeChapter, let fullUrl = URL(string: href, relativeTo: baseUrl)?.absoluteString, !seen.contains(fullUrl) {
                    seen.insert(fullUrl)
                    heuristic.append(Chapter(index: idx, title: title, url: fullUrl))
                    idx += 1
                }
            }
            if heuristic.count >= 3 {
                chapters = heuristic
            }
        }
        
        // 4. Trim leading "Latest Chapters" preview block if Chapter 1 appears within indices 1...15
        if chapters.count > 10 {
            let maxCheck = min(15, chapters.count - 1)
            for idx in 1...maxCheck {
                let t = chapters[idx].title.trimmingCharacters(in: .whitespacesAndNewlines)
                let isFirstChapter = t.hasPrefix("第一章") || t.hasPrefix("第1章") || t.hasPrefix("第01章")
                    || t.hasPrefix("第001章") || t.hasPrefix("楔子") || t.hasPrefix("序章") || t.hasPrefix("引子")
                let firstTitle = chapters[0].title
                let firstIsAlreadyCh1 = firstTitle.hasPrefix("第一章") || firstTitle.hasPrefix("第1章")
                    || firstTitle.hasPrefix("楔子") || firstTitle.hasPrefix("序章") || firstTitle.hasPrefix("引子")
                if isFirstChapter && !firstIsAlreadyCh1 {
                    let trimmed = Array(chapters[idx...])
                    chapters = trimmed.enumerated().map { newIdx, ch in
                        Chapter(index: newIdx, title: ch.title, url: ch.url, isCached: ch.isCached)
                    }
                    break
                }
            }
        }
        
        return chapters
    }
    
    private func extractChapters(from elements: [Element], nameRule: String, urlRule: String, baseUrl: URL) -> [Chapter] {
        var chapters: [Chapter] = []
        var seenUrls = Set<String>()
        var index = 0
        
        for el in elements {
            let title = extractValue(from: el, rule: nameRule, baseUrl: baseUrl)
                ?? extractValue(from: el, rule: "a@text||text", baseUrl: baseUrl)
                ?? ""
            guard let url = extractValue(from: el, rule: urlRule, baseUrl: baseUrl)
                ?? extractValue(from: el, rule: "a@href||href", baseUrl: baseUrl) else {
                continue
            }
            
            if !title.isEmpty && !url.isEmpty && !url.hasPrefix("javascript") && !seenUrls.contains(url) {
                seenUrls.insert(url)
                chapters.append(Chapter(index: index, title: title, url: url))
                index += 1
            }
        }
        return chapters
    }
    
    // MARK: - Chapter Content Parsing + Smart Fallback
    public func parseContent(html: String, baseUrl: URL, source: BookSource) throws -> String {
        let doc = try SwiftSoup.parse(html, baseUrl.absoluteString)
        
        if let ruleContent = source.ruleContent?.content, !ruleContent.isEmpty {
            // Prefer @html over @text so paragraph breaks (<br>, <p>) are preserved
            let htmlRule: String
            if ruleContent.hasSuffix("@text") {
                htmlRule = String(ruleContent.dropLast(5)) + "@html"
            } else {
                htmlRule = ruleContent
            }
            if let extracted = extractValue(from: doc, rule: htmlRule, baseUrl: baseUrl)
                ?? extractValue(from: doc, rule: ruleContent, baseUrl: baseUrl) {
                var raw = extracted
                if let replaceRegex = source.ruleContent?.replaceRegex, !replaceRegex.isEmpty {
                    let cleanPattern = replaceRegex.hasPrefix("##") ? String(replaceRegex.dropFirst(2)) : replaceRegex
                    let parts = cleanPattern.components(separatedBy: "##")
                    if let pattern = parts.first, !pattern.isEmpty {
                        let rep = parts.count > 1 ? parts[1] : ""
                        raw = raw.replacingOccurrences(of: pattern, with: rep, options: .regularExpression)
                    }
                }
                let cleaned = cleanNovelText(raw)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        
        // Smart Auto-Discovery Fallback for common novel content containers
        let fallbackRules = [
            "#content@html", "#chaptercontent@html", ".read-content@html",
            "#booktxt@html", ".con@html", "#nr1@html", "#nr@html", ".txtnav@html",
            ".word_read@html", ".content@html", "#TextContent@html", "#rtext@html", "article@html"
        ]
        for rule in fallbackRules {
            if let raw = extractValue(from: doc, rule: rule, baseUrl: baseUrl) {
                let cleaned = cleanNovelText(raw)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        
        throw ChapterLoadingError.missingContent
    }
    
    // MARK: - Clean HTML to Reader Prose (Paragraph-Preserving)
    private func cleanNovelText(_ rawHtml: String) -> String {
        var text = rawHtml
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        
        // 1. Convert all HTML block / line-break tags into newlines (case-insensitive)
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<p[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<div[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // 2. Decode HTML entities; convert 2+ consecutive non-breaking or full-width spaces into paragraph breaks!
        text = text.replacingOccurrences(of: "(&nbsp;|&#160;|&#xA0;|\\u{00A0}|\\u{3000}){2,}", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "&#160;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&ldquo;", with: "“")
        text = text.replacingOccurrences(of: "&rdquo;", with: "”")
        text = text.replacingOccurrences(of: "&hellip;", with: "…")
        text = text.replacingOccurrences(of: "&mdash;", with: "—")
        
        // 3. Also split where sentence-ending punctuation is followed by 2+ spaces
        text = text.replacingOccurrences(
            of: "([。！？…”」』】])[ \\t\\u{00A0}\\u{3000}]{2,}",
            with: "$1\n",
            options: .regularExpression
        )
        
        let adKeywords = [
            "请记住本站域名", "手机阅读", "最新章节请访问", "一秒记住",
            "天才一秒记住", "本章未完", "点击下一页继续阅读", "为防止内容获取不全",
            "请勿使用浏览器阅读模式", "加入书签，方便阅读"
        ]
        
        let rawLines = text.components(separatedBy: .newlines)
        var formattedLines: [String] = []
        
        for rawLine in rawLines {
            let trimmed = rawLine
                .replacingOccurrences(of: "\u{3000}", with: " ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Do not erase narrative sentences merely because they mention reading on a phone.
            let pagingNotice = trimmed.range(of: "^(?:本章未完[，,。]?\\s*)?(?:请|請)?(?:点击|點擊)?下一[页頁](?:继续阅读|繼續閱讀)[。.!！]?$", options: .regularExpression) != nil
            if pagingNotice || adKeywords.contains(where: { trimmed == $0 || trimmed == $0 + "。" }) {
                continue
            }
            formattedLines.append("　　" + trimmed)
        }
        
        return formattedLines.joined(separator: "\n\n")
    }
}
