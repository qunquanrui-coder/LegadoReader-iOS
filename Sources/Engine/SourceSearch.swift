import Foundation
import Combine

/// Cap concurrent requests, not the number of sources the user can search.
public enum SourceSearchPolicy {
    public static func unsupportedReason(_ source: BookSource) -> String? {
        guard (source.bookSourceType ?? 0) == 0 else { return "暂不支持此书源类型" }
        guard let url = source.searchUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let list = source.ruleSearch?.bookList, !list.isEmpty else { return "缺少搜索规则" }
        let wholeRule = list.trimmingCharacters(in: .whitespacesAndNewlines)
        if wholeRule.hasPrefix("<js>") || wholeRule.hasPrefix("@js:") {
            return "暂不支持 JavaScript 搜索列表规则"
        }
        let alternatives = list.components(separatedBy: "||")
        if alternatives.allSatisfy({ rule in
            let rule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            return rule.hasPrefix("$") || rule.hasPrefix("@json:") || rule.hasPrefix("@js:")
                || rule.hasPrefix("<js>") || rule.hasPrefix("//") || rule.hasPrefix("@XPath:")
        }) { return "暂不支持此搜索列表规则" }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        ChapterTextFormatter.normalizeTitle(text.replacingOccurrences(of: "作者：", with: "")
            .replacingOccurrences(of: "作者:", with: ""))
    }

    private static func knownAuthor(_ author: String) -> Bool {
        !["", "佚名", "未知", "未知作者", "暂无"].contains(normalized(author))
    }

    public static func isCandidate(_ candidate: Book, for book: Book) -> Bool {
        guard !normalized(book.title).isEmpty, normalized(candidate.title) == normalized(book.title) else { return false }
        return !knownAuthor(book.author) || !knownAuthor(candidate.author)
            || normalized(book.author) == normalized(candidate.author)
    }

    public static func needsAuthorConfirmation(_ candidate: Book, for book: Book) -> Bool {
        !knownAuthor(book.author) || !knownAuthor(candidate.author)
    }
}

public enum SourceSearchService {
    public static func search(source: BookSource, keyword: String) async throws -> [Book] {
        try Task.checkCancellation()
        let (html, url) = try await NetworkManager.shared.executeSearch(source: source, keyword: keyword)
        try Task.checkCancellation()
        return try LegadoParser.shared.parseSearch(html: html, baseUrl: url, source: source)
    }
}

/// A new query, clearing the field, or leaving the screen invalidates all old callbacks.
@MainActor
public final class SourceSearchSession: ObservableObject {
    public typealias Search = (BookSource, String) async throws -> [Book]
    @Published public private(set) var results: [Book] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var status = ""
    @Published public private(set) var hasMore = false
    @Published public private(set) var finished = 0
    @Published public private(set) var failures = 0
    @Published public private(set) var emptyResults = 0
    @Published public private(set) var unsupported = 0
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var sources: [BookSource] = []
    private var keyword = ""
    private var offset = 0
    private var targetBook: Book?
    private let search: Search
    private let batchSize: Int
    private let concurrency: Int

    public init(batchSize: Int = 35, concurrency: Int = 6,
                search: @escaping Search = { try await SourceSearchService.search(source: $0, keyword: $1) }) {
        self.batchSize = max(1, batchSize)
        self.concurrency = max(1, concurrency)
        self.search = search
    }

    public func start(keyword: String, sources: [BookSource], matching book: Book? = nil) {
        clear()
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !self.keyword.isEmpty else { return }
        let enabled = sources.filter { $0.enabled ?? true }
        self.sources = enabled.filter { SourceSearchPolicy.unsupportedReason($0) == nil }
        unsupported = enabled.count - self.sources.count
        targetBook = book
        hasMore = !self.sources.isEmpty
        continueSearch()
    }

    public func clear() {
        cancel()
        results = []; sources = []; offset = 0; finished = 0
        failures = 0; emptyResults = 0; unsupported = 0; hasMore = false; status = ""
    }

    public func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
        isSearching = false
        if !status.isEmpty { updateStatus(prefix: "已停止") }
    }

    private func updateStatus(prefix: String) {
        status = "\(prefix) · 已查 \(finished)/\(sources.count) 源 · \(results.count) 条结果 · 无匹配 \(emptyResults) · 请求/解析失败 \(failures) · 不支持 \(unsupported)"
    }

    public func continueSearch() {
        guard !isSearching else { return }
        guard offset < sources.count else { hasMore = false; updateStatus(prefix: "搜索结束"); return }
        isSearching = true
        let id = generation
        let query = keyword
        let worker = search
        let target = targetBook
        updateStatus(prefix: "搜索中")
        task = Task { [weak self] in
            guard let self = self else { return }
            repeat {
                let initialCount = self.results.count
                let end = min(self.offset + self.batchSize, self.sources.count)
                let batch = Array(self.sources[self.offset..<end])
                // Only advance offset after a request completes; cancellation must not skip unsearched sources.
                for chunkStart in stride(from: 0, to: batch.count, by: self.concurrency) {
                    guard !Task.isCancelled, self.generation == id else { return }
                    let chunk = Array(batch[chunkStart..<min(chunkStart + self.concurrency, batch.count)])
                    let responses = await withTaskGroup(of: [Book]?.self) { group -> [[Book]?] in
                        for source in chunk {
                            group.addTask {
                                guard !Task.isCancelled else { return nil }
                                return try? await worker(source, query)
                            }
                        }
                        var responses: [[Book]?] = []
                        for await response in group {
                            if Task.isCancelled { group.cancelAll() }
                            responses.append(response)
                        }
                        return responses
                    }
                    guard !Task.isCancelled, self.generation == id else { return }
                    // Commit a chunk atomically so stopping/resuming cannot double-count partial work.
                    for response in responses {
                        self.finished += 1
                        if let response = response {
                            let books = response.filter { candidate in
                                target.map { SourceSearchPolicy.isCandidate(candidate, for: $0) } ?? true
                            }
                            if books.isEmpty { self.emptyResults += 1 }
                            var seen = Set(self.results.map { $0.sourceUrl + "\n" + $0.bookUrl })
                            self.results.append(contentsOf: books.filter { seen.insert($0.sourceUrl + "\n" + $0.bookUrl).inserted })
                        } else { self.failures += 1 }
                    }
                    self.updateStatus(prefix: "搜索中")
                    self.offset += chunk.count
                    self.hasMore = self.offset < self.sources.count
                }
                // Empty/failed batches automatically fall through to the remaining sources.
                if self.results.count > initialCount { break }
            } while self.offset < self.sources.count
            guard !Task.isCancelled, self.generation == id else { return }
            self.isSearching = false
            self.updateStatus(prefix: self.hasMore ? "本批完成，可继续搜索" : "搜索结束")
        }
    }
}

public enum SourceImportPolicy {
    public struct Result {
        public var sources: [BookSource]
        public var added = 0
        public var updated = 0
        public var skipped = 0
    }

    public static func merge(existing: [BookSource], incoming: [BookSource], updateExisting: Bool) -> Result {
        var result = Result(sources: existing)
        var indices = Dictionary(existing.enumerated().map { ($0.element.bookSourceUrl, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for source in incoming {
            guard !source.bookSourceUrl.isEmpty, !source.bookSourceName.isEmpty else { result.skipped += 1; continue }
            if let index = indices[source.bookSourceUrl] {
                guard updateExisting else { result.skipped += 1; continue }
                var updated = source
                updated.enabled = result.sources[index].enabled
                // Rule changes invalidate previous validation timings, but never the user's enable switch.
                updated.respondTime = nil
                result.sources[index] = updated
                result.updated += 1
            } else {
                indices[source.bookSourceUrl] = result.sources.count
                result.sources.append(source)
                result.added += 1
            }
        }
        return result
    }
}

public enum SourceValidationPolicy {
    public static func validate(sources: [BookSource], keyword: String = "斗罗大陆",
                                search: @escaping SourceSearchSession.Search = { try await SourceSearchService.search(source: $0, keyword: $1) },
                                progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> [BookSource] {
        var tested: [BookSource] = []
        for start in stride(from: 0, to: sources.count, by: 6) {
            try Task.checkCancellation()
            let batch = Array(sources[start..<min(start + 6, sources.count)])
            let results = await withTaskGroup(of: BookSource.self) { group -> [BookSource] in
                for source in batch {
                    group.addTask {
                        var result = source
                        guard source.enabled ?? true else { return result }
                        guard !Task.isCancelled, SourceSearchPolicy.unsupportedReason(source) == nil else {
                            result.respondTime = 99999
                            return result
                        }
                        let started = Date()
                        if let books = try? await search(source, keyword), !books.isEmpty {
                            result.respondTime = min(89999, max(1, Int(Date().timeIntervalSince(started) * 1000)))
                        } else { result.respondTime = 99999 }
                        return result
                    }
                }
                var values: [BookSource] = []
                for await result in group { values.append(result) }
                return values
            }
            try Task.checkCancellation()
            tested.append(contentsOf: results)
            await progress(tested.count, sources.count)
        }
        return tested
    }

    /// Merge into the live list: don't resurrect deleted sources, discard imports, or change enable switches.
    public static func applying(_ tested: [BookSource], original: [BookSource], to current: [BookSource]) -> [BookSource] {
        let originals = Dictionary(original.map { ($0.bookSourceUrl, $0) }, uniquingKeysWith: { first, _ in first })
        let timings = Dictionary(tested.map { ($0.bookSourceUrl, $0.respondTime ?? 99999) }, uniquingKeysWith: { first, _ in first })
        return current.enumerated().map { index, source -> (Int, BookSource) in
            var updated = source
            if var old = originals[source.bookSourceUrl] {
                old.enabled = source.enabled; old.respondTime = source.respondTime
                if old == source, let time = timings[source.bookSourceUrl] { updated.respondTime = time }
            }
            return (index, updated)
        }.sorted { a, b in
            let at = (a.1.enabled ?? true) ? (a.1.respondTime ?? 99999) : 99999
            let bt = (b.1.enabled ?? true) ? (b.1.respondTime ?? 99999) : 99999
            return at == bt ? a.0 < b.0 : at < bt
        }.map { $0.1 }
    }
}
