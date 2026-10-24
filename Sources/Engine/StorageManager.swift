import Foundation
import Combine

public class StorageManager: ObservableObject {
    public static let shared = StorageManager()
    
    @Published public var bookshelf: [Book] = []
    @Published public var bookSources: [BookSource] = []
    @Published public var readerConfig: ReaderConfig = .default
    @Published public var searchHistory: [String] = []
    @Published public var lastReadBookId: String? = nil
    
    private let bookshelfKey = "LegadoReader_Bookshelf_v2"
    private let sourcesKey = "LegadoReader_BookSources_v2_1"
    private let configKey = "LegadoReader_ReaderConfig_v2"
    private let historyKey = "LegadoReader_SearchHistory_v2"
    private let positionMapKey = "LegadoReader_PositionMap_v3_1"
    private let chapterTitleMapKey = "LegadoReader_ChapterTitleMap_v3_2"
    private let lastReadBookIdKey = "LegadoReader_LastReadBookId_v3_2"
    private let pendingRelocationKey = "LegadoReader_PendingRelocation_v3_2_1"
    
    private let fileManager = FileManager.default
    
    /// Chapter cache lives in Library/Application Support (excluded from iCloud backup),
    /// instead of Documents which would silently consume the user's iCloud storage.
    public let cacheDirectoryURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("NovelCache_v4_complete", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()
    
    private var cacheDirectory: URL {
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
        return cacheDirectoryURL
    }
    
    /// Legacy caches have no completeness metadata and must be downloaded again.
    private func migrateLegacyCacheIfNeeded() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyDirectories = [docs.appendingPathComponent("NovelCache_v2_1"),
                                 docs.appendingPathComponent("NovelCache"),
                                 support.appendingPathComponent("NovelCache_v3")]
        ChapterContentCache(directory: cacheDirectory).quarantineLegacyCaches(at: legacyDirectories)
    }
    
    /// Total size of all cached chapters in bytes
    public func chapterCacheSizeBytes() -> Int64 {
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: cacheDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }
    
    /// Removes every cached chapter (bookshelf & reading progress are kept)
    public func clearAllChapterCache() {
        if let items = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil) {
            for item in items {
                try? fileManager.removeItem(at: item)
            }
        }
    }
    
    /// Removes cached chapters of a single book (used after switching book source)
    public func clearChapterCache(bookId: String) {
        try? fileManager.removeItem(at: cacheDirectoryURL.appendingPathComponent(bookId))
    }
    
    private static func bookKey(title: String, author: String) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines))_\(author.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    
    /// Returns the last saved chapter title of a book (if any)
    public func savedChapterTitle(for book: Book) -> String? {
        let key = Self.bookKey(title: book.title, author: book.author)
        if let map = UserDefaults.standard.dictionary(forKey: chapterTitleMapKey) as? [String: String],
           let t = map[key], !t.isEmpty {
            return t
        }
        if let shelfBook = bookshelf.first(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }),
           let t = shelfBook.currentChapterTitle, !t.isEmpty {
            return t
        }
        return book.currentChapterTitle
    }
    
    /// After a source switch, the reader must re-locate the current chapter by title in the new TOC.
    /// Returns (and clears) the chapter title to re-locate, if a source switch happened.
    public func consumePendingRelocation(for book: Book) -> String? {
        let key = Self.bookKey(title: book.title, author: book.author)
        var map = (UserDefaults.standard.dictionary(forKey: pendingRelocationKey) as? [String: String]) ?? [:]
        guard let title = map.removeValue(forKey: key) else { return nil }
        UserDefaults.standard.set(map, forKey: pendingRelocationKey)
        return title
    }
    
    private func setPendingRelocation(for book: Book, chapterTitle: String) {
        let key = Self.bookKey(title: book.title, author: book.author)
        var map = (UserDefaults.standard.dictionary(forKey: pendingRelocationKey) as? [String: String]) ?? [:]
        map[key] = chapterTitle
        UserDefaults.standard.set(map, forKey: pendingRelocationKey)
    }
    
    /// Returns the most recently read book for the top "最近阅读" card on the bookshelf
    public var mostRecentBook: Book? {
        if let lastId = lastReadBookId,
           let matched = bookshelf.first(where: { $0.id == lastId }) {
            return matched
        }
        return bookshelf.max(by: { $0.lastReadTime < $1.lastReadTime }) ?? bookshelf.first
    }
    
    private init() {
        migrateLegacyCacheIfNeeded()
        loadData()
    }
    
    public func loadData() {
        if let configData = UserDefaults.standard.data(forKey: configKey),
           let savedConfig = try? JSONDecoder().decode(ReaderConfig.self, from: configData) {
            self.readerConfig = savedConfig
        }
        
        self.lastReadBookId = UserDefaults.standard.string(forKey: lastReadBookIdKey)
        
        if let shelfData = UserDefaults.standard.data(forKey: bookshelfKey),
           let savedShelf = try? JSONDecoder().decode([Book].self, from: shelfData) {
            self.bookshelf = savedShelf
        } else if let legacyShelfData = UserDefaults.standard.data(forKey: "LegadoReader_Bookshelf"),
                  let legacyShelf = try? JSONDecoder().decode([Book].self, from: legacyShelfData) {
            self.bookshelf = legacyShelf
        }
        
        // Sort bookshelf so the most recently read book is at the top on launch
        if bookshelf.count > 1 {
            bookshelf.sort { a, b in
                if a.id == lastReadBookId { return true }
                if b.id == lastReadBookId { return false }
                return a.lastReadTime > b.lastReadTime
            }
        }
        
        if let hist = UserDefaults.standard.stringArray(forKey: historyKey) {
            self.searchHistory = hist
        }
        
        if let sourcesData = UserDefaults.standard.data(forKey: sourcesKey),
           let savedSources = try? JSONDecoder().decode([BookSource].self, from: sourcesData),
           !savedSources.isEmpty {
            self.bookSources = savedSources
        } else {
            loadDefaultSources()
        }
    }
    
    public func addSearchHistory(_ keyword: String) {
        let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        searchHistory.removeAll(where: { $0 == clean })
        searchHistory.insert(clean, at: 0)
        if searchHistory.count > 12 {
            searchHistory = Array(searchHistory.prefix(12))
        }
        UserDefaults.standard.set(searchHistory, forKey: historyKey)
    }
    
    public func clearSearchHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
    
    // MARK: - BookShelf Operations
    public func addBookToShelf(_ book: Book) {
        if let idx = bookshelf.firstIndex(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            bookshelf[idx].sourceUrl = book.sourceUrl
            bookshelf[idx].sourceName = book.sourceName
            bookshelf[idx].bookUrl = book.bookUrl
            if let cover = book.coverUrl, !cover.isEmpty {
                bookshelf[idx].coverUrl = cover
            }
            saveBookshelf()
        } else {
            var newBook = book
            if lastReadBookId == nil {
                lastReadBookId = newBook.id
                UserDefaults.standard.set(newBook.id, forKey: lastReadBookIdKey)
            }
            bookshelf.append(newBook)
            saveBookshelf()
        }
    }
    
    /// Marks a book as the actively read book right now, moving it to index 0 and updating `lastReadBookId`
    public func markBookAsRecentlyRead(_ book: Book) {
        let now = Date()
        if let idx = bookshelf.firstIndex(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            var updated = bookshelf[idx]
            updated.lastReadTime = now
            if let cover = book.coverUrl, !cover.isEmpty, (updated.coverUrl == nil || updated.coverUrl!.isEmpty) {
                updated.coverUrl = cover
            }
            lastReadBookId = updated.id
            UserDefaults.standard.set(updated.id, forKey: lastReadBookIdKey)
            if idx != 0 {
                bookshelf.remove(at: idx)
                bookshelf.insert(updated, at: 0)
            } else {
                bookshelf[0] = updated
            }
            saveBookshelf()
        } else {
            var newBook = book
            newBook.lastReadTime = now
            lastReadBookId = newBook.id
            UserDefaults.standard.set(newBook.id, forKey: lastReadBookIdKey)
            bookshelf.insert(newBook, at: 0)
            saveBookshelf()
        }
    }
    
    public func replaceBookSource(for book: Book, with newBook: Book) -> Book {
        let sourceChanged = (book.sourceUrl != newBook.sourceUrl) || (book.bookUrl != newBook.bookUrl)
        var updated = book
        updated.sourceUrl = newBook.sourceUrl
        updated.sourceName = newBook.sourceName
        updated.bookUrl = newBook.bookUrl
        if let latest = newBook.latestChapter, !latest.isEmpty {
            updated.latestChapter = latest
        }
        if sourceChanged {
            // Old cached chapters belong to the previous source's TOC numbering — they must not be reused.
            clearChapterCache(bookId: book.id)
            if let shelfBook = bookshelf.first(where: { $0.title == book.title && $0.author == book.author }), shelfBook.id != book.id {
                clearChapterCache(bookId: shelfBook.id)
            }
            if let chapterTitle = savedChapterTitle(for: book), !chapterTitle.isEmpty {
                setPendingRelocation(for: book, chapterTitle: chapterTitle)
            }
        }
        if let idx = bookshelf.firstIndex(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            bookshelf[idx].sourceUrl = updated.sourceUrl
            bookshelf[idx].sourceName = updated.sourceName
            bookshelf[idx].bookUrl = updated.bookUrl
            if let latest = updated.latestChapter { bookshelf[idx].latestChapter = latest }
            updated.id = bookshelf[idx].id
            saveBookshelf()
        }
        return updated
    }
    
    public func removeBookFromShelf(_ book: Book) {
        let removedIds = bookshelf.filter { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }.map { $0.id }
        bookshelf.removeAll(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) })
        if let last = lastReadBookId, removedIds.contains(last) || last == book.id {
            lastReadBookId = bookshelf.max(by: { $0.lastReadTime < $1.lastReadTime })?.id
            UserDefaults.standard.set(lastReadBookId, forKey: lastReadBookIdKey)
        }
        saveBookshelf()
        for id in Set(removedIds + [book.id]) {
            clearChapterCache(bookId: id)
        }
    }
    
    public func updateBookProgress(
        bookId: String,
        bookTitle: String? = nil,
        bookAuthor: String? = nil,
        chapterIndex: Int,
        chapterTitle: String,
        totalChapters: Int,
        paragraphIndex: Int = 0
    ) {
        let now = Date()
        if let index = bookshelf.firstIndex(where: {
            $0.id == bookId || (bookTitle != nil && $0.title == bookTitle && $0.author == bookAuthor)
        }) {
            var updated = bookshelf[index]
            updated.currentChapterIndex = chapterIndex
            updated.currentChapterTitle = chapterTitle
            updated.currentParagraphIndex = paragraphIndex
            updated.totalChapters = max(updated.totalChapters, totalChapters)
            updated.lastReadTime = now
            
            let t = updated.title
            let a = updated.author
            lastReadBookId = updated.id
            UserDefaults.standard.set(updated.id, forKey: lastReadBookIdKey)
            
            if index != 0 {
                bookshelf.remove(at: index)
                bookshelf.insert(updated, at: 0)
            } else {
                bookshelf[0] = updated
            }
            
            savePositionEntry(title: t, author: a, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex, chapterTitle: chapterTitle)
            saveBookshelf()
        } else if let t = bookTitle, let a = bookAuthor {
            savePositionEntry(title: t, author: a, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex, chapterTitle: chapterTitle)
        }
    }
    
    private func savePositionEntry(title: String, author: String, chapterIndex: Int, paragraphIndex: Int, chapterTitle: String? = nil) {
        let key = "\(title.trimmingCharacters(in: .whitespacesAndNewlines))_\(author.trimmingCharacters(in: .whitespacesAndNewlines))"
        var map = (UserDefaults.standard.dictionary(forKey: positionMapKey) as? [String: [Int]]) ?? [:]
        map[key] = [chapterIndex, paragraphIndex]
        UserDefaults.standard.set(map, forKey: positionMapKey)
        
        if let chTitle = chapterTitle, !chTitle.isEmpty {
            var titleMap = (UserDefaults.standard.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
            titleMap[key] = chTitle
            UserDefaults.standard.set(titleMap, forKey: chapterTitleMapKey)
        }
    }
    
    public func getSavedReadingPosition(for book: Book) -> (chapterIndex: Int, paragraphIndex: Int) {
        let key = "\(book.title.trimmingCharacters(in: .whitespacesAndNewlines))_\(book.author.trimmingCharacters(in: .whitespacesAndNewlines))"
        if let map = UserDefaults.standard.dictionary(forKey: positionMapKey) as? [String: [Int]],
           let pair = map[key], pair.count >= 2 {
            return (pair[0], pair[1])
        }
        if let shelfBook = bookshelf.first(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            return (shelfBook.currentChapterIndex, shelfBook.currentParagraphIndex ?? 0)
        }
        return (book.currentChapterIndex, book.currentParagraphIndex ?? 0)
    }
    
    public func saveBookshelf() {
        if let data = try? JSONEncoder().encode(bookshelf) {
            UserDefaults.standard.set(data, forKey: bookshelfKey)
        }
    }
    
    // MARK: - BookSource Operations
    public func saveBookSources() {
        if let data = try? JSONEncoder().encode(bookSources) {
            UserDefaults.standard.set(data, forKey: sourcesKey)
        }
    }
    
    public func importSourcesFromJSON(jsonString: String) throws -> Int {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "LegadoReader", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的文本编码"])
        }
        
        let decoder = JSONDecoder()
        var newSources: [BookSource] = []
        
        if let single = try? decoder.decode(BookSource.self, from: data) {
            newSources = [single]
        } else if let lossyList = try? decoder.decode(LossyCodableList<BookSource>.self, from: data),
                  !lossyList.elements.isEmpty {
            newSources = lossyList.elements
        } else {
            throw NSError(domain: "LegadoReader", code: -2, userInfo: [NSLocalizedDescriptionKey: "书源 JSON 格式不符合 Legado 规范"])
        }
        
        var existingSet = Set(bookSources.map { $0.bookSourceUrl })
        var addedCount = 0
        
        for s in newSources {
            guard !s.bookSourceUrl.isEmpty, !s.bookSourceName.isEmpty else { continue }
            if !existingSet.contains(s.bookSourceUrl) {
                existingSet.insert(s.bookSourceUrl)
                bookSources.append(s)
                addedCount += 1
            }
        }
        
        saveBookSources()
        return addedCount
    }
    
    public func loadDefaultSources() {
        if let url = Bundle.main.url(forResource: "default_sources", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let lossyList = try? JSONDecoder().decode(LossyCodableList<BookSource>.self, from: data) {
            self.bookSources = lossyList.elements
            saveBookSources()
        }
    }
    
    // MARK: - Chapter Cache Operations
    public func getCachedChapter(bookId: String, chapterIndex: Int, chapterURL: String, sourceURL: String) -> String? {
        ChapterContentCache(directory: cacheDirectory).read(bookId: bookId, chapterIndex: chapterIndex,
                                                           chapterURL: chapterURL, sourceURL: sourceURL)
    }
    
    public func isChapterCached(bookId: String, chapterIndex: Int, chapterURL: String? = nil, sourceURL: String? = nil) -> Bool {
        ChapterContentCache(directory: cacheDirectory).read(bookId: bookId, chapterIndex: chapterIndex,
                                                           chapterURL: chapterURL, sourceURL: sourceURL) != nil
    }
    
    @discardableResult
    public func saveChapterCache(bookId: String, chapterIndex: Int, content: CompleteChapterContent) -> Bool {
        if let shelfBook = bookshelf.first(where: { $0.id == bookId }), shelfBook.sourceUrl != content.sourceURL {
            return false
        }
        return ChapterContentCache(directory: cacheDirectory).save(content, bookId: bookId, chapterIndex: chapterIndex)
    }
    
    public func saveConfig() {
        if let data = try? JSONEncoder().encode(readerConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
    
    // MARK: - Full Data Backup & Restore (Bookshelf + Progress + Sources + Config)
    public struct FullBackupPayload: Codable {
        public var version: String = "3.3.0"
        public var exportedAt: Date = Date()
        public var bookshelf: [Book]
        public var bookSources: [BookSource]
        public var readerConfig: ReaderConfig
        public var lastReadBookId: String?
        public var positionMap: [String: [Int]]
        public var chapterTitleMap: [String: String]
    }
    
    public func exportFullBackupJSON() -> String? {
        let posMap = (UserDefaults.standard.dictionary(forKey: positionMapKey) as? [String: [Int]]) ?? [:]
        let titleMap = (UserDefaults.standard.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
        let payload = FullBackupPayload(
            bookshelf: bookshelf,
            bookSources: bookSources,
            readerConfig: readerConfig,
            lastReadBookId: lastReadBookId,
            positionMap: posMap,
            chapterTitleMap: titleMap
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    public func exportFullBackupFileURL() -> URL? {
        guard let json = exportFullBackupJSON() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let filename = "风读全量备份_\(formatter.string(from: Date())).json"
        let fileURL = fileManager.temporaryDirectory.appendingPathComponent(filename)
        try? json.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    public func restoreFromBackupJSON(_ jsonString: String) throws -> (booksCount: Int, sourcesCount: Int) {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "LegadoReader", code: -10, userInfo: [NSLocalizedDescriptionKey: "备份文本编码无效"])
        }
        let decoder = JSONDecoder()
        let payload = try decoder.decode(FullBackupPayload.self, from: data)
        
        // 1. Restore reader config
        self.readerConfig = payload.readerConfig
        saveConfig()
        
        // 2. Merge position maps
        var posMap = (UserDefaults.standard.dictionary(forKey: positionMapKey) as? [String: [Int]]) ?? [:]
        for (k, v) in payload.positionMap { posMap[k] = v }
        UserDefaults.standard.set(posMap, forKey: positionMapKey)
        
        var titleMap = (UserDefaults.standard.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
        for (k, v) in payload.chapterTitleMap { titleMap[k] = v }
        UserDefaults.standard.set(titleMap, forKey: chapterTitleMapKey)
        
        // 3. Merge bookshelf
        for incoming in payload.bookshelf {
            if let idx = bookshelf.firstIndex(where: { $0.id == incoming.id || ($0.title == incoming.title && $0.author == incoming.author) }) {
                if incoming.lastReadTime >= bookshelf[idx].lastReadTime || incoming.currentChapterIndex > bookshelf[idx].currentChapterIndex {
                    bookshelf[idx] = incoming
                }
            } else {
                bookshelf.append(incoming)
            }
        }
        if let lastId = payload.lastReadBookId {
            self.lastReadBookId = lastId
            UserDefaults.standard.set(lastId, forKey: lastReadBookIdKey)
        }
        saveBookshelf()
        
        // 4. Merge book sources
        var existingUrls = Set(bookSources.map { $0.bookSourceUrl })
        for s in payload.bookSources {
            if !s.bookSourceUrl.isEmpty && !existingUrls.contains(s.bookSourceUrl) {
                existingUrls.insert(s.bookSourceUrl)
                bookSources.append(s)
            }
        }
        saveBookSources()
        
        return (payload.bookshelf.count, payload.bookSources.count)
    }
}
