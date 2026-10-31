import Foundation
import Combine

public class StorageManager: ObservableObject {
    public static let shared: StorageManager = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suite = "LegadoReader_UITests_v3_8"
            guard let testDefaults = UserDefaults(suiteName: suite) else {
                fatalError("UI tests require an isolated defaults suite")
            }
            testDefaults.removePersistentDomain(forName: suite)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LegadoReaderUITests_\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("cache", isDirectory: true)
            let store = StorageManager(defaults: testDefaults, cacheDirectoryURL: directory, loadDefaults: false)
            store.bookSources = [BookSource(bookSourceName: "UI测试自定义源", bookSourceUrl: "https://fixture.invalid/custom")]
            store.saveBookSources()
            return store
        }
        #endif
        return StorageManager()
    }()
    
    @Published public var bookshelf: [Book] = []
    @Published public var bookSources: [BookSource] = []
    @Published public var readerConfig: ReaderConfig = .default
    @Published public var searchHistory: [String] = []
    @Published public var lastReadBookId: String? = nil
    public private(set) var readerConfigUpdatedAt: Date?
    
    private let bookshelfKey = "LegadoReader_Bookshelf_v2"
    private let sourcesKey = "LegadoReader_BookSources_v2_1"
    private let configKey = "LegadoReader_ReaderConfig_v2"
    private let historyKey = "LegadoReader_SearchHistory_v2"
    private let positionMapKey = "LegadoReader_PositionMap_v3_1"
    private let chapterTitleMapKey = "LegadoReader_ChapterTitleMap_v3_2"
    private let lastReadBookIdKey = "LegadoReader_LastReadBookId_v3_2"
    private let pendingRelocationKey = "LegadoReader_PendingRelocation_v3_2_1"
    private let configUpdatedAtKey = "LegadoReader_ReaderConfigUpdatedAt_v3_8"
    private let defaults: UserDefaults
    private let onBookRemoval: ((Book) -> Void)?
    private let writeLock = NSRecursiveLock()
    private var bookGenerations: [String: UUID] = [:]
    private var deletedBookIDs: Set<String> = []
    private var deletedBookKeys: Set<String> = []
    private var bookKeysByID: [String: String] = [:]
    
    private let fileManager = FileManager.default
    
    /// Chapter cache lives in Library/Application Support (excluded from iCloud backup),
    /// instead of Documents which would silently consume the user's iCloud storage.
    private static func defaultCacheDirectory() -> URL {
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
    }
    public let cacheDirectoryURL: URL
    
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
    
    /// Calculates directory size in bytes without touching actor-isolated state so callers can run it off the main thread.
    public static func directorySizeBytes(at directoryURL: URL) -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    /// Total size of all cached chapters in bytes
    public func chapterCacheSizeBytes() -> Int64 {
        Self.directorySizeBytes(at: cacheDirectoryURL)
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
    
    static func bookKey(title: String, author: String) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines))_\(author.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    
    /// Returns the last saved chapter title of a book (if any)
    public func savedChapterTitle(for book: Book) -> String? {
        let key = Self.bookKey(title: book.title, author: book.author)
        if let map = defaults.dictionary(forKey: chapterTitleMapKey) as? [String: String],
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
        var map = (defaults.dictionary(forKey: pendingRelocationKey) as? [String: String]) ?? [:]
        guard let title = map.removeValue(forKey: key) else { return nil }
        defaults.set(map, forKey: pendingRelocationKey)
        return title
    }
    
    private func setPendingRelocation(for book: Book, chapterTitle: String) {
        let key = Self.bookKey(title: book.title, author: book.author)
        var map = (defaults.dictionary(forKey: pendingRelocationKey) as? [String: String]) ?? [:]
        map[key] = chapterTitle
        defaults.set(map, forKey: pendingRelocationKey)
    }
    
    /// Returns the most recently read book for the top "最近阅读" card on the bookshelf
    public var mostRecentBook: Book? {
        if let lastId = lastReadBookId,
           let matched = bookshelf.first(where: { $0.id == lastId }) {
            return matched
        }
        return bookshelf.max(by: { $0.lastReadTime < $1.lastReadTime }) ?? bookshelf.first
    }
    
    private convenience init() {
        self.init(defaults: .standard, cacheDirectoryURL: Self.defaultCacheDirectory(), loadDefaults: false)
        migrateLegacyCacheIfNeeded()
        loadData()
    }

    /// Isolated storage for regression tests and previews; never migrates production caches.
    init(defaults: UserDefaults, cacheDirectoryURL: URL, loadDefaults: Bool = true,
         onBookRemoval: ((Book) -> Void)? = nil) {
        self.defaults = defaults
        self.cacheDirectoryURL = cacheDirectoryURL
        self.onBookRemoval = onBookRemoval
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        if loadDefaults { loadData() }
    }

    public func bookWriteToken(for book: Book) -> BookWriteToken {
        writeLock.lock(); defer { writeLock.unlock() }
        let key = Self.bookKey(title: book.title, author: book.author)
        bookKeysByID[book.id] = key
        let generation = bookGenerations[key] ?? UUID()
        bookGenerations[key] = generation
        return BookWriteToken(bookID: book.id, logicalKey: key, generation: generation,
                              sourceURL: book.sourceUrl, bookURL: book.bookUrl)
    }

    public func acceptsBookWrite(_ token: BookWriteToken) -> Bool {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !deletedBookIDs.contains(token.bookID), !deletedBookKeys.contains(token.logicalKey),
              bookGenerations[token.logicalKey] == token.generation else { return false }
        if let current = bookshelf.first(where: { $0.id == token.bookID || Self.bookKey(title: $0.title, author: $0.author) == token.logicalKey }) {
            return current.sourceUrl == token.sourceURL && current.bookUrl == token.bookURL
        }
        return true
    }

    private func permitsWrite(bookId: String, logicalKey: String? = nil, token: BookWriteToken?) -> Bool {
        if let token { return acceptsBookWrite(token) && token.bookID == bookId }
        let key = logicalKey ?? bookKeysByID[bookId]
        return !deletedBookIDs.contains(bookId) && !(key.map { deletedBookKeys.contains($0) } ?? false)
    }

    private func activateBook(_ book: Book) {
        let key = Self.bookKey(title: book.title, author: book.author)
        bookKeysByID[book.id] = key
        if deletedBookKeys.remove(key) != nil {
            bookGenerations[key] = UUID()
            deletedBookIDs = deletedBookIDs.filter { bookKeysByID[$0] != key }
        }
        deletedBookIDs.remove(book.id)
    }
    
    public func loadData() {
        readerConfigUpdatedAt = defaults.object(forKey: configUpdatedAtKey) as? Date
        if let configData = defaults.data(forKey: configKey),
           let savedConfig = try? JSONDecoder().decode(ReaderConfig.self, from: configData) {
            self.readerConfig = savedConfig
        }
        
        self.lastReadBookId = defaults.string(forKey: lastReadBookIdKey)
        
        if let shelfData = defaults.data(forKey: bookshelfKey),
           let savedShelf = try? JSONDecoder().decode([Book].self, from: shelfData) {
            self.bookshelf = savedShelf
        } else if let legacyShelfData = defaults.data(forKey: "LegadoReader_Bookshelf"),
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
        
        if let hist = defaults.stringArray(forKey: historyKey) {
            self.searchHistory = hist
        }
        
        if let sourcesData = defaults.data(forKey: sourcesKey),
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
        defaults.set(searchHistory, forKey: historyKey)
    }
    
    public func clearSearchHistory() {
        searchHistory.removeAll()
        defaults.removeObject(forKey: historyKey)
    }
    
    // MARK: - BookShelf Operations
    /// Return the shelf's canonical identity so TOC and text downloads use the same cache directory.
    @discardableResult
    public func addBookToShelf(_ book: Book) -> Book {
        writeLock.lock(); defer { writeLock.unlock() }
        activateBook(book)
        if let existing = bookshelf.first(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            return replaceBookSource(for: existing, with: book)
        }
        if lastReadBookId == nil {
            lastReadBookId = book.id
            defaults.set(book.id, forKey: lastReadBookIdKey)
        }
        bookshelf.append(book)
        saveBookshelf()
        return book
    }

    /// Keep shelf identity and reading state when the same work is found on a different site.
    static func bookByReplacingSource(of existing: Book, with incoming: Book) -> Book {
        var updated = existing
        if existing.sourceUrl != incoming.sourceUrl || existing.bookUrl != incoming.bookUrl {
            // Character offsets refer to the old site's formatted paragraph text.
            updated.currentCharacterOffset = 0
        }
        updated.sourceUrl = incoming.sourceUrl
        updated.sourceName = incoming.sourceName
        updated.bookUrl = incoming.bookUrl
        if let latest = incoming.latestChapter, !latest.isEmpty { updated.latestChapter = latest }
        if let cover = incoming.coverUrl, !cover.isEmpty { updated.coverUrl = cover }
        return updated
    }

    /// Marks a book as the actively read book right now, moving it to index 0 and updating `lastReadBookId`
    public func markBookAsRecentlyRead(_ book: Book) {
        writeLock.lock(); defer { writeLock.unlock() }
        activateBook(book)
        let now = Date()
        if let idx = bookshelf.firstIndex(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            var updated = bookshelf[idx]
            updated.lastReadTime = now
            if let cover = book.coverUrl, !cover.isEmpty, (updated.coverUrl == nil || updated.coverUrl!.isEmpty) {
                updated.coverUrl = cover
            }
            lastReadBookId = updated.id
            defaults.set(updated.id, forKey: lastReadBookIdKey)
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
            defaults.set(newBook.id, forKey: lastReadBookIdKey)
            bookshelf.insert(newBook, at: 0)
            saveBookshelf()
        }
    }
    
    public func replaceBookSource(for book: Book, with newBook: Book) -> Book {
        writeLock.lock(); defer { writeLock.unlock() }
        let shelfIndex = bookshelf.firstIndex(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) })
        let original = shelfIndex.map { bookshelf[$0] } ?? book
        let sourceChanged = (original.sourceUrl != newBook.sourceUrl) || (original.bookUrl != newBook.bookUrl)
        let updated = Self.bookByReplacingSource(of: original, with: newBook)
        if sourceChanged {
            bookGenerations[Self.bookKey(title: original.title, author: original.author)] = UUID()
            let savedPosition = getSavedReadingPosition(for: original)
            savePositionEntry(title: original.title, author: original.author,
                              chapterIndex: savedPosition.chapterIndex, paragraphIndex: savedPosition.paragraphIndex,
                              characterOffset: 0)
            // Always invalidate the canonical shelf cache, including switches initiated from a search result.
            clearChapterCache(bookId: original.id)
            if book.id != original.id { clearChapterCache(bookId: book.id) }
            if let chapterTitle = savedChapterTitle(for: original), !chapterTitle.isEmpty {
                setPendingRelocation(for: original, chapterTitle: chapterTitle)
            }
        }
        if let index = shelfIndex {
            bookshelf[index] = updated
            saveBookshelf()
        }
        return updated
    }

    public func removeBookFromShelf(_ book: Book) {
        writeLock.lock(); defer { writeLock.unlock() }
        let removedBooks = bookshelf.filter { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }
        let removedIds = removedBooks.map { $0.id }
        let removedKeys = Set((removedBooks + [book]).map { Self.bookKey(title: $0.title, author: $0.author) })
        for record in removedBooks + [book] {
            let key = Self.bookKey(title: record.title, author: record.author)
            bookKeysByID[record.id] = key
            deletedBookIDs.insert(record.id)
            deletedBookKeys.insert(key)
            bookGenerations[key] = UUID()
        }
        if let onBookRemoval { onBookRemoval(book) }
        else { SpeechSynthesizerManager.shared.stopIfReading(book: book) }
        bookshelf.removeAll(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) })
        if let last = lastReadBookId, removedIds.contains(last) || last == book.id {
            lastReadBookId = bookshelf.max(by: { $0.lastReadTime < $1.lastReadTime })?.id
            defaults.set(lastReadBookId, forKey: lastReadBookIdKey)
        }
        saveBookshelf()
        let posStore = ReadingPositionStore(defaults: defaults, key: positionMapKey)
        var titleMap = (defaults.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
        var relocationMap = (defaults.dictionary(forKey: pendingRelocationKey) as? [String: String]) ?? [:]
        for key in removedKeys {
            posStore.remove(for: key)
            titleMap.removeValue(forKey: key)
            relocationMap.removeValue(forKey: key)
        }
        defaults.set(titleMap, forKey: chapterTitleMapKey)
        defaults.set(relocationMap, forKey: pendingRelocationKey)
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
        paragraphIndex: Int = 0,
        characterOffset: Int = 0,
        writeToken: BookWriteToken? = nil
    ) {
        writeLock.lock(); defer { writeLock.unlock() }
        let key = bookTitle.flatMap { title in bookAuthor.map { Self.bookKey(title: title, author: $0) } }
        guard permitsWrite(bookId: bookId, logicalKey: key, token: writeToken) else { return }
        let now = Date()
        if let index = bookshelf.firstIndex(where: {
            $0.id == bookId || (bookTitle != nil && $0.title == bookTitle && $0.author == bookAuthor)
        }) {
            var updated = bookshelf[index]
            updated.currentChapterIndex = chapterIndex
            updated.currentChapterTitle = chapterTitle
            updated.currentParagraphIndex = paragraphIndex
            updated.currentCharacterOffset = max(0, characterOffset)
            updated.totalChapters = max(updated.totalChapters, totalChapters)
            updated.lastReadTime = now
            
            let t = updated.title
            let a = updated.author
            lastReadBookId = updated.id
            defaults.set(updated.id, forKey: lastReadBookIdKey)
            
            if index != 0 {
                bookshelf.remove(at: index)
                bookshelf.insert(updated, at: 0)
            } else {
                bookshelf[0] = updated
            }
            
            savePositionEntry(title: t, author: a, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex,
                              characterOffset: characterOffset, chapterTitle: chapterTitle)
            saveBookshelf()
        } else if let t = bookTitle, let a = bookAuthor {
            savePositionEntry(title: t, author: a, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex,
                              characterOffset: characterOffset, chapterTitle: chapterTitle)
        }
    }
    
    private func savePositionEntry(title: String, author: String, chapterIndex: Int, paragraphIndex: Int,
                                   characterOffset: Int = 0, chapterTitle: String? = nil) {
        let key = Self.bookKey(title: title, author: author)
        ReadingPositionStore(defaults: defaults, key: positionMapKey).set(
            StoredReadingPosition(chapterIndex: chapterIndex, paragraphIndex: paragraphIndex, characterOffset: characterOffset),
            for: key)
        
        if let chTitle = chapterTitle, !chTitle.isEmpty {
            var titleMap = (defaults.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
            titleMap[key] = chTitle
            defaults.set(titleMap, forKey: chapterTitleMapKey)
        }
    }
    
    public func getSavedReadingPosition(for book: Book) -> (chapterIndex: Int, paragraphIndex: Int, characterOffset: Int) {
        let key = Self.bookKey(title: book.title, author: book.author)
        if let saved = ReadingPositionStore(defaults: defaults, key: positionMapKey).position(for: key) {
            return (saved.chapterIndex, saved.paragraphIndex, saved.characterOffset)
        }
        if let shelfBook = bookshelf.first(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            return (shelfBook.currentChapterIndex, shelfBook.currentParagraphIndex ?? 0, max(0, shelfBook.currentCharacterOffset ?? 0))
        }
        return (book.currentChapterIndex, book.currentParagraphIndex ?? 0, max(0, book.currentCharacterOffset ?? 0))
    }
    
    public func saveBookshelf() {
        if let data = try? JSONEncoder().encode(bookshelf) {
            defaults.set(data, forKey: bookshelfKey)
        }
    }
    
    // MARK: - BookSource Operations
    public func saveBookSources() {
        if let data = try? JSONEncoder().encode(bookSources) {
            defaults.set(data, forKey: sourcesKey)
        }
    }
    
    public func importSourcesFromJSON(jsonString: String, updateExisting: Bool = false) throws -> SourceImportPolicy.Result {
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
        
        let result = SourceImportPolicy.merge(existing: bookSources, incoming: newSources, updateExisting: updateExisting)
        bookSources = result.sources
        saveBookSources()
        return result
    }
    
    private func bundledSources() -> [BookSource] {
        guard let url = Bundle.main.url(forResource: "default_sources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(LossyCodableList<BookSource>.self, from: data) else { return [] }
        return list.elements
    }

    /// Replenish missing built-ins without overwriting imported rules, custom edits or enable switches.
    @discardableResult
    public func loadDefaultSources() -> Int {
        let result = SourceImportPolicy.merge(existing: bookSources, incoming: bundledSources(), updateExisting: false)
        bookSources = result.sources
        saveBookSources()
        return result.added
    }

    private var sourceResetSnapshotURL: URL {
        cacheDirectoryURL.deletingLastPathComponent().appendingPathComponent("BookSourceResetSnapshot_v1.json")
    }

    public var hasSourceResetSnapshot: Bool { fileManager.fileExists(atPath: sourceResetSnapshotURL.path) }

    /// The caller must present a destructive-action confirmation. A failed snapshot never resets rules.
    @discardableResult
    public func resetSourcesToDefaults() throws -> URL {
        let builtIns = bundledSources()
        guard !builtIns.isEmpty else { throw NSError(domain: "LegadoReader", code: -20,
            userInfo: [NSLocalizedDescriptionKey: "内置书源未能读取，已保留当前书源"] ) }
        let snapshot = sourceResetSnapshotURL
        try fileManager.createDirectory(at: snapshot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(bookSources).write(to: snapshot, options: .atomic)
        bookSources = builtIns
        saveBookSources()
        return snapshot
    }

    @discardableResult
    public func restoreSourcesFromLastResetSnapshot() throws -> Int {
        let restored = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: sourceResetSnapshotURL))
        // Restoring the pre-reset rules must not erase sources imported after that reset.
        bookSources = SourceImportPolicy.merge(existing: restored, incoming: bookSources, updateExisting: false).sources
        saveBookSources()
        return bookSources.count
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

    public func cachedChapterIndices(bookId: String, sourceURL: String? = nil, chapters: [Chapter]? = nil) -> Set<Int> {
        ChapterContentCache(directory: cacheDirectory).cachedChapterIndices(bookId: bookId, sourceURL: sourceURL, chapters: chapters)
    }
    
    // MARK: - TOC Persistence (offline catalogue)
    /// Persisted chapter list for a book — without it even fully cached chapters cannot be opened offline.
    public func loadCachedToc(for book: Book) -> TocSnapshot? {
        TocCache(directory: cacheDirectory).read(bookId: book.id, sourceURL: book.sourceUrl, bookURL: book.bookUrl)
    }
    
    @discardableResult
    public func saveCachedToc(for book: Book, chapters: [Chapter], complete: Bool, writeToken: BookWriteToken? = nil) -> Bool {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !chapters.isEmpty,
              permitsWrite(bookId: book.id, logicalKey: Self.bookKey(title: book.title, author: book.author), token: writeToken) else { return false }
        if let current = bookshelf.first(where: { $0.id == book.id }),
           current.sourceUrl != book.sourceUrl || current.bookUrl != book.bookUrl { return false }
        return TocCache(directory: cacheDirectory).save(bookId: book.id, sourceURL: book.sourceUrl,
                                                        bookURL: book.bookUrl, chapters: chapters, complete: complete)
    }
    
    public func removeCachedToc(bookId: String) {
        TocCache(directory: cacheDirectory).remove(bookId: bookId)
    }
    
    @discardableResult
    public func saveChapterCache(bookId: String, chapterIndex: Int, content: CompleteChapterContent, writeToken: BookWriteToken? = nil) -> Bool {
        writeLock.lock(); defer { writeLock.unlock() }
        guard permitsWrite(bookId: bookId, token: writeToken) else { return false }
        if let shelfBook = bookshelf.first(where: { $0.id == bookId }), shelfBook.sourceUrl != content.sourceURL {
            return false
        }
        return ChapterContentCache(directory: cacheDirectory).save(content, bookId: bookId, chapterIndex: chapterIndex)
    }
    
    public func saveConfig(updatedAt: Date = Date()) {
        if let data = try? JSONEncoder().encode(readerConfig) {
            defaults.set(data, forKey: configKey)
            readerConfigUpdatedAt = updatedAt
            defaults.set(updatedAt, forKey: configUpdatedAtKey)
        }
    }
    
    // MARK: - Full Data Backup & Restore (Bookshelf + Progress + Sources + Config)
    public struct FullBackupPayload: Codable {
        public var version: String = "3.4.0"
        public var exportedAt: Date = Date()
        public var bookshelf: [Book]
        public var bookSources: [BookSource]
        public var readerConfig: ReaderConfig
        public var lastReadBookId: String?
        public var positionMap: [String: [Int]]
        public var chapterTitleMap: [String: String]
        public var readerConfigUpdatedAt: Date? = nil
    }
    
    /// Capture value state on the caller's UI actor; encoding and writing can then run elsewhere.
    public func makeFullBackupPayload() -> FullBackupPayload {
        writeLock.lock(); defer { writeLock.unlock() }
        let posMap = (defaults.dictionary(forKey: positionMapKey) as? [String: [Int]]) ?? [:]
        let titleMap = (defaults.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
        return FullBackupPayload(
            bookshelf: bookshelf,
            bookSources: bookSources,
            readerConfig: readerConfig,
            lastReadBookId: lastReadBookId,
            positionMap: posMap,
            chapterTitleMap: titleMap,
            readerConfigUpdatedAt: readerConfigUpdatedAt
        )
    }

    public func exportFullBackupJSON() -> String? {
        let payload = makeFullBackupPayload()
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
    
    // MARK: - Backup Merge Rules
    /// Single "who is further along" rule: the newer read wins, and on a tie the higher
    /// chapter index wins. The shelf, the position map and the reader all consume this one
    /// decision, so a stale backup can never half-roll-back a newer reading position.
    static func isNewerReadingState(_ incoming: Book, than local: Book) -> Bool {
        if incoming.lastReadTime != local.lastReadTime {
            return incoming.lastReadTime > local.lastReadTime
        }
        return incoming.currentChapterIndex > local.currentChapterIndex
    }

    /// Merges a backup into the current shelf, then rebuilds the position/title maps from
    /// the merged shelf so all three stores always agree.
    static func mergeBackupState(
        localBooks: [Book],
        localPositions: [String: [Int]],
        localTitles: [String: String],
        backupBooks: [Book],
        backupPositions: [String: [Int]],
        backupTitles: [String: String],
        sourcePolicy: BackupSourcePolicy = .keepLocal
    ) -> (bookshelf: [Book], positions: [String: [Int]], titles: [String: String], relocations: [String: String]) {
        var merged = localBooks
        var relocations: [String: String] = [:]
        for incoming in backupBooks {
            if let index = merged.firstIndex(where: {
                $0.id == incoming.id || ($0.title == incoming.title && $0.author == incoming.author)
            }) {
                if isNewerReadingState(incoming, than: merged[index]) {
                    var updated = incoming
                    updated.id = merged[index].id
                    if sourcePolicy == .keepLocal,
                       incoming.sourceUrl != merged[index].sourceUrl || incoming.bookUrl != merged[index].bookUrl {
                        // Chapter numbers and text offsets are source-specific. Keep usable local
                        // downloads, and resolve the incoming chapter title against the local TOC.
                        updated = merged[index]
                        updated.lastReadTime = incoming.lastReadTime
                        if let title = incoming.currentChapterTitle, !title.isEmpty {
                            relocations[bookKey(title: incoming.title, author: incoming.author)] = title
                        }
                    }
                    merged[index] = updated
                }
            } else {
                merged.append(incoming)
            }
        }

        var positions = localPositions
        var titles = localTitles
        let shelfKeys = Set(merged.map { bookKey(title: $0.title, author: $0.author) })

        // Keep legacy map-only entries from the backup when no shelf record exists for them.
        for (key, pair) in backupPositions where !shelfKeys.contains(key) {
            if positions[key] == nil { positions[key] = pair }
        }
        for (key, title) in backupTitles where !shelfKeys.contains(key) {
            if titles[key] == nil { titles[key] = title }
        }

        // The merged shelf is the single source of truth; rewrite every entry so the
        // bookshelf card, the reader's getSavedReadingPosition() and the title cache agree.
        for book in merged {
            let key = bookKey(title: book.title, author: book.author)
            positions[key] = StoredReadingPosition(chapterIndex: book.currentChapterIndex,
                                                   paragraphIndex: book.currentParagraphIndex ?? 0,
                                                   characterOffset: book.currentCharacterOffset ?? 0).values
            if let chapterTitle = book.currentChapterTitle, !chapterTitle.isEmpty {
                titles[key] = chapterTitle
            }
        }
        return (merged, positions, titles, relocations)
    }

    /// A configuration is one user-authored snapshot. Mixing older rules or nil/default
    /// values back in can resurrect preferences the user deliberately removed.
    static func mergeReaderConfig(local: ReaderConfig, backup: ReaderConfig, preferLocal: Bool = false) -> ReaderConfig {
        preferLocal ? local : backup
    }

    /// Selects the most recently read book ID between local and backup so an older backup
    /// does not point the top "最近阅读" card at a stale book.
    static func resolveLastReadBookId(
        localLastReadId: String?,
        backupLastReadId: String?,
        mergedShelf: [Book],
        backupBooks: [Book] = []
    ) -> String? {
        let localBook = localLastReadId.flatMap { id in
            mergedShelf.first(where: { $0.id == id })
        }
        let backupBook: Book? = backupLastReadId.flatMap { id in
            if let direct = mergedShelf.first(where: { $0.id == id }) { return direct }
            if let orig = backupBooks.first(where: { $0.id == id }) {
                return mergedShelf.first(where: { $0.title == orig.title && $0.author == orig.author })
            }
            return nil
        }
        if let l = localBook, let b = backupBook {
            return isNewerReadingState(b, than: l) ? b.id : l.id
        }
        if let b = backupBook { return b.id }
        if let l = localBook { return l.id }
        return mergedShelf.max(by: { isNewerReadingState($1, than: $0) })?.id
    }

    public func restoreFromBackupJSON(_ jsonString: String, sourcePolicy: BackupSourcePolicy = .keepLocal,
                                      configPolicy: BackupConfigPolicy = .newest) throws -> (booksCount: Int, sourcesCount: Int) {
        writeLock.lock(); defer { writeLock.unlock() }
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "LegadoReader", code: -10, userInfo: [NSLocalizedDescriptionKey: "备份文本编码无效"])
        }
        let decoder = JSONDecoder()
        let payload = try decoder.decode(FullBackupPayload.self, from: data)
        
        let keepLocalConfig: Bool
        switch configPolicy {
        case .keepLocal: keepLocalConfig = true
        case .useBackup: keepLocalConfig = false
        case .newest:
            if defaults.data(forKey: configKey) == nil { keepLocalConfig = false }
            else if let localDate = readerConfigUpdatedAt, let backupDate = payload.readerConfigUpdatedAt {
                keepLocalConfig = localDate >= backupDate
            } else {
                // Legacy backups do not prove that their preferences are newer. Preserve the
                // current install unless the user explicitly requests the backup's settings.
                keepLocalConfig = true
            }
        }
        switch configPolicy {
        case .keepLocal: break
        case .useBackup: self.readerConfig = payload.readerConfig
        case .newest:
            self.readerConfig = Self.mergeReaderConfig(local: readerConfig, backup: payload.readerConfig,
                                                       preferLocal: keepLocalConfig)
        }
        saveConfig(updatedAt: (keepLocalConfig ? readerConfigUpdatedAt : payload.readerConfigUpdatedAt) ?? Date())
        
        // 2. Merge the shelf and rebuild the position maps from the merged result in one go.
        //    A stale backup must not keep the newer shelf row while rolling the position map back.
        let currentPositions = (defaults.dictionary(forKey: positionMapKey) as? [String: [Int]]) ?? [:]
        let currentTitles = (defaults.dictionary(forKey: chapterTitleMapKey) as? [String: String]) ?? [:]
        let mergedState = Self.mergeBackupState(
            localBooks: bookshelf,
            localPositions: currentPositions,
            localTitles: currentTitles,
            backupBooks: payload.bookshelf,
            backupPositions: payload.positionMap,
            backupTitles: payload.chapterTitleMap,
            sourcePolicy: sourcePolicy
        )
        var restoredBooks = mergedState.bookshelf
        var restoredPositions = mergedState.positions
        var restoredTitles = mergedState.titles
        for index in restoredBooks.indices {
            let record = restoredBooks[index]
            let key = Self.bookKey(title: record.title, author: record.author)
            if let targetTitle = mergedState.relocations[key] {
                if let toc = loadCachedToc(for: record),
                   let match = ChapterTextFormatter.bestMatchIndex(title: targetTitle, in: toc.chapters, nearIndex: record.currentChapterIndex) {
                    restoredBooks[index].currentChapterIndex = match
                    restoredBooks[index].currentChapterTitle = toc.chapters[match].title
                    restoredBooks[index].currentParagraphIndex = 0
                    restoredBooks[index].currentCharacterOffset = 0
                    restoredPositions[key] = [match, 0]
                    restoredTitles[key] = toc.chapters[match].title
                } else { setPendingRelocation(for: record, chapterTitle: targetTitle) }
            }
            if let local = bookshelf.first(where: { $0.id == record.id }),
               local.sourceUrl != record.sourceUrl || local.bookUrl != record.bookUrl {
                writeLock.lock()
                bookGenerations[key] = UUID()
                if let onBookRemoval { onBookRemoval(local) }
                else { SpeechSynthesizerManager.shared.stopIfReading(book: local) }
                clearChapterCache(bookId: local.id)
                writeLock.unlock()
            }
            // Importing a backup is an explicit restoration; stale pre-delete requests remain
            // invalid because activation changes their generation.
            writeLock.lock(); activateBook(record); writeLock.unlock()
        }
        let resolvedLastId = Self.resolveLastReadBookId(
            localLastReadId: lastReadBookId,
            backupLastReadId: payload.lastReadBookId,
            mergedShelf: restoredBooks,
            backupBooks: payload.bookshelf
        )
        self.lastReadBookId = resolvedLastId
        defaults.set(resolvedLastId, forKey: lastReadBookIdKey)

        var sortedShelf = restoredBooks
        if sortedShelf.count > 1 {
            sortedShelf.sort { a, b in
                if a.id == resolvedLastId { return true }
                if b.id == resolvedLastId { return false }
                return Self.isNewerReadingState(a, than: b)
            }
        }
        self.bookshelf = sortedShelf
        saveBookshelf()
        defaults.set(restoredPositions, forKey: positionMapKey)
        defaults.set(restoredTitles, forKey: chapterTitleMapKey)
        
        // 3. Merge book sources
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
