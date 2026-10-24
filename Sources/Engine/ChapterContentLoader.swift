import Foundation
import SwiftSoup

/// Only a successful, fully traversed chapter may be written to the chapter cache.
public struct CompleteChapterContent {
    public let text: String
    public let chapterURL: String
    public let sourceURL: String
    public let pageCount: Int
}

public enum ChapterLoadingError: LocalizedError {
    case missingContent
    case incompletePage(Int)
    case paginationLoop
    case pageLimit
    case differentChapter
    case ambiguousNextPage

    public var errorDescription: String? {
        switch self {
        case .missingContent: return "未能解析章节正文，请重试或切换书源。"
        case .incompletePage(let page): return "本章尚未加载完整：第 \(page) 页加载失败，请重试。"
        case .paginationLoop: return "本章分页链接重复，正文尚未加载完整，请重试或切换书源。"
        case .pageLimit: return "本章分页数量异常，正文尚未加载完整，请切换书源。"
        case .differentChapter: return "书源分页指向了其他章节，已停止加载，请切换书源。"
        case .ambiguousNextPage: return "检测到本章还有后续页，但无法确认分页链接，请重试或切换书源。"
        }
    }
}

/// Shared by the reader, prefetch, downloads and detached speech playback.
public final class ChapterContentLoader {
    public typealias FetchPage = (String, String?) async throws -> (String, URL)
    public static let shared = ChapterContentLoader()
    private let fetchPage: FetchPage
    private let maxPages: Int

    public init(maxPages: Int = 100, fetchPage: @escaping FetchPage = {
        try await NetworkManager.shared.fetchString(from: $0, referer: $1)
    }) {
        self.maxPages = max(1, maxPages)
        self.fetchPage = fetchPage
    }

    public func load(chapter: Chapter, source: BookSource, referer: String?,
                     nextChapterURL: String? = nil) async throws -> CompleteChapterContent {
        var requestedURL = chapter.url
        var previousURL = referer
        var visited = Set<String>()
        var pages: [String] = []
        var firstURL: URL?

        while true {
            try Task.checkCancellation()
            guard pages.count < maxPages else { throw ChapterLoadingError.pageLimit }
            let requestedKey = canonicalURL(requestedURL)
            guard visited.insert(requestedKey).inserted else { throw ChapterLoadingError.paginationLoop }
            let html: String
            let finalURL: URL
            do {
                (html, finalURL) = try await fetchPage(requestedURL, previousURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if pages.isEmpty { throw error }
                throw ChapterLoadingError.incompletePage(pages.count + 1)
            }
            try Task.checkCancellation()
            let finalKey = canonicalURL(finalURL.absoluteString)
            if finalKey != requestedKey {
                guard visited.insert(finalKey).inserted else { throw ChapterLoadingError.paginationLoop }
            }
            if firstURL == nil { firstURL = finalURL }
            let doc = try SwiftSoup.parse(html, finalURL.absoluteString)
            try validateChapterTitle(doc, expected: chapter.title)
            let text = try LegadoParser.shared.parseContent(html: html, baseUrl: finalURL, source: source)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChapterLoadingError.missingContent
            }
            // Repeated pages under different URLs are not evidence of a complete chapter.
            guard pages.last != text else { throw ChapterLoadingError.paginationLoop }
            pages.append(text)

            guard let next = try nextPage(in: doc, baseURL: finalURL, firstURL: firstURL!,
                                          source: source, nextChapterURL: nextChapterURL) else { break }
            previousURL = finalURL.absoluteString
            requestedURL = next
        }
        try Task.checkCancellation()
        return CompleteChapterContent(text: pages.joined(separator: "\n\n"), chapterURL: chapter.url,
                                      sourceURL: source.bookSourceUrl, pageCount: pages.count)
    }

    private func nextPage(in doc: Document, baseURL: URL, firstURL: URL,
                          source: BookSource, nextChapterURL: String?) throws -> String? {
        let pageText = (try? doc.body()?.text()) ?? ""
        let pagingElements = (try? doc.select("h1, title, .pagination, .pager, .pagebar").array()) ?? []
        let counterShowsMore = pagingElements.contains { element in
            let value = (try? element.text()) ?? ""
            guard let expression = try? NSRegularExpression(pattern: "(\\d+)\\s*[/／]\\s*(\\d+)"),
                  let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let currentRange = Range(match.range(at: 1), in: value),
                  let totalRange = Range(match.range(at: 2), in: value),
                  let current = Int(value[currentRange]), let total = Int(value[totalRange]) else { return false }
            return current < total
        }
        let unfinished = counterShowsMore || pageText.range(of: "本章未完|本章未完結|点击下一页|點擊下一頁|下一页继续|下一頁繼續",
                                                           options: .regularExpression) != nil
        let anchors = (try? doc.select("a[href]").array()) ?? []
        var candidate: String?
        var fromRule = false
        if let rule = source.ruleContent?.nextContentUrl, !rule.isEmpty {
            candidate = LegadoParser.shared.extractValue(from: doc, rule: rule, baseUrl: baseURL)
            fromRule = candidate != nil
        }
        if candidate == nil {
            for anchor in anchors {
                let label = (try? anchor.text()) ?? ""
                let compact = label.replacingOccurrences(of: "\\s+|[»›>→]", with: "", options: .regularExpression).lowercased()
                let isNextPage = ["下一页", "下页", "下一頁", "下頁", "nextpage"].contains(compact)
                if anchor.hasAttr("disabled") || (try? anchor.attr("aria-disabled")) == "true" { continue }
                if isNextPage, let href = try? anchor.attr("href"), !href.isEmpty {
                    candidate = href
                    break
                }
            }
        }
        guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            if unfinished { throw ChapterLoadingError.ambiguousNextPage }
            return nil
        }
        let key = canonicalURL(url.absoluteString)
        let disabledTarget = anchors.contains { anchor in
            guard let href = try? anchor.attr("href"), let target = URL(string: href, relativeTo: baseURL),
                  canonicalURL(target.absoluteString) == key else { return false }
            return href == "#" || anchor.hasAttr("disabled") || (try? anchor.attr("aria-disabled")) == "true"
        }
        if disabledTarget {
            if unfinished { throw ChapterLoadingError.ambiguousNextPage }
            return nil
        }
        let pointsToNextChapter = nextChapterURL.map { canonicalURL($0) == key } ?? false
        let labelSaysNextChapter = anchors.contains { anchor in
            guard let href = try? anchor.attr("href"),
                  let target = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  canonicalURL(target.absoluteString) == key else { return false }
            let label = (try? anchor.text()) ?? ""
            return label.contains("下一章") || label.contains("下章") || label.lowercased().contains("next chapter")
        }
        if pointsToNextChapter || labelSaysNextChapter {
            if unfinished { throw ChapterLoadingError.ambiguousNextPage }
            return nil
        }
        guard url.host?.lowercased() == firstURL.host?.lowercased() else {
            throw ChapterLoadingError.ambiguousNextPage
        }
        // A source's explicit rule is authoritative. Generic links require the same chapter URL stem.
        if !fromRule && chapterStem(url) != chapterStem(firstURL) {
            throw ChapterLoadingError.ambiguousNextPage
        }
        return url.absoluteString
    }

    private func validateChapterTitle(_ doc: Document, expected: String) throws {
        let title = (try? doc.select("h1").first()?.text()) ?? ""
        guard title.range(of: "第[0-9零〇一二两三四五六七八九十百千万]+[章节回]", options: .regularExpression) != nil else { return }
        func normalized(_ value: String) -> String {
            let withoutPage = value.replacingOccurrences(of: "[（(]\\s*\\d+\\s*[/／]\\s*\\d+\\s*[)）]|第\\s*\\d+\\s*页",
                                                        with: "", options: .regularExpression)
            return ChapterTextFormatter.normalizeTitle(withoutPage)
        }
        let expectedTitle = normalized(expected)
        guard !expectedTitle.isEmpty else { return }
        if let actualNumber = chapterNumber(title), let expectedNumber = chapterNumber(expected) {
            guard actualNumber == expectedNumber else { throw ChapterLoadingError.differentChapter }
            return
        }
        guard normalized(title).contains(expectedTitle) else { throw ChapterLoadingError.differentChapter }
    }

    private func chapterNumber(_ title: String) -> Int? {
        guard let token = ChapterTextFormatter.chapterNumberToken(title) else { return nil }
        if let number = Int(token) { return number }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                         "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        var total = 0, section = 0, digit = 0
        for character in token {
            if let value = digits[character] { digit = value }
            else if let unit = units[character] { section += max(1, digit) * unit; digit = 0 }
            else if character == "万" { total += (section + digit) * 10_000; section = 0; digit = 0 }
            else { return nil }
        }
        return total + section + digit
    }

    private func chapterStem(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
        components.fragment = nil
        let filteredQuery = components.queryItems?.filter { !["page", "p", "pageno"].contains($0.name.lowercased()) }
        components.queryItems = filteredQuery?.isEmpty == true ? nil : filteredQuery
        components.path = url.path.replacingOccurrences(of: "[_-]\\d+(?=\\.[A-Za-z]+$)", with: "", options: .regularExpression)
        return components.string ?? url.absoluteString
    }

    private func canonicalURL(_ value: String) -> String {
        let clean = value.components(separatedBy: ",{").first ?? value
        var components = URLComponents(string: clean)
        components?.fragment = nil
        return components?.string ?? clean
    }
}
