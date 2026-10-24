import Foundation
import Combine

public class StorageManager: ObservableObject {
    public static let shared = StorageManager()
    
    @Published public var bookshelf: [Book] = []
    @Published public var bookSources: [BookSource] = []
    @Published public var readerConfig: ReaderConfig = .default
    @Published public var searchHistory: [String] = []
    
    private let bookshelfKey = "LegadoReader_Bookshelf_v2"
    private let sourcesKey = "LegadoReader_BookSources_v2"
    private let configKey = "LegadoReader_ReaderConfig_v2"
    private let historyKey = "LegadoReader_SearchHistory_v2"
    
    private let fileManager = FileManager.default
    private var cacheDirectory: URL {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("NovelCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {
        loadData()
    }
    
    public func loadData() {
        if let configData = UserDefaults.standard.data(forKey: configKey),
           let savedConfig = try? JSONDecoder().decode(ReaderConfig.self, from: configData) {
            self.readerConfig = savedConfig
        }
        
        if let shelfData = UserDefaults.standard.data(forKey: bookshelfKey),
           let savedShelf = try? JSONDecoder().decode([Book].self, from: shelfData) {
            self.bookshelf = savedShelf
        } else if let legacyShelfData = UserDefaults.standard.data(forKey: "LegadoReader_Bookshelf"),
                  let legacyShelf = try? JSONDecoder().decode([Book].self, from: legacyShelfData) {
            self.bookshelf = legacyShelf
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
        if let idx = bookshelf.firstIndex(where: { $0.title == book.title && $0.author == book.author }) {
            bookshelf[idx].sourceUrl = book.sourceUrl
            bookshelf[idx].sourceName = book.sourceName
            bookshelf[idx].bookUrl = book.bookUrl
            if let cover = book.coverUrl, !cover.isEmpty {
                bookshelf[idx].coverUrl = cover
            }
            saveBookshelf()
        } else {
            bookshelf.insert(book, at: 0)
            saveBookshelf()
        }
    }
    
    public func replaceBookSource(for book: Book, with newBook: Book) -> Book {
        var updated = book
        updated.sourceUrl = newBook.sourceUrl
        updated.sourceName = newBook.sourceName
        updated.bookUrl = newBook.bookUrl
        if let latest = newBook.latestChapter, !latest.isEmpty {
            updated.latestChapter = latest
        }
        if let idx = bookshelf.firstIndex(where: { $0.id == book.id || ($0.title == book.title && $0.author == book.author) }) {
            bookshelf[idx] = updated
            saveBookshelf()
        }
        return updated
    }
    
    public func removeBookFromShelf(_ book: Book) {
        bookshelf.removeAll(where: { $0.id == book.id })
        saveBookshelf()
        let bookDir = cacheDirectory.appendingPathComponent(book.id)
        try? fileManager.removeItem(at: bookDir)
    }
    
    public func updateBookProgress(bookId: String, chapterIndex: Int, chapterTitle: String, totalChapters: Int) {
        if let index = bookshelf.firstIndex(where: { $0.id == bookId }) {
            bookshelf[index].currentChapterIndex = chapterIndex
            bookshelf[index].currentChapterTitle = chapterTitle
            bookshelf[index].totalChapters = max(bookshelf[index].totalChapters, totalChapters)
            bookshelf[index].lastReadTime = Date()
            saveBookshelf()
        }
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
            // Skip pure JS sources that cannot be parsed without Rhino/QuickJS
            if let su = s.searchUrl, (su.hasPrefix("@js:") || su.hasPrefix("<js>")) {
                continue
            }
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
    public func getCachedChapter(bookId: String, chapterIndex: Int) -> String? {
        let filePath = cacheDirectory.appendingPathComponent(bookId).appendingPathComponent("\(chapterIndex).txt")
        return try? String(contentsOf: filePath, encoding: .utf8)
    }
    
    public func isChapterCached(bookId: String, chapterIndex: Int) -> Bool {
        let filePath = cacheDirectory.appendingPathComponent(bookId).appendingPathComponent("\(chapterIndex).txt")
        return fileManager.fileExists(atPath: filePath.path)
    }
    
    public func saveChapterCache(bookId: String, chapterIndex: Int, content: String) {
        let bookDir = cacheDirectory.appendingPathComponent(bookId)
        if !fileManager.fileExists(atPath: bookDir.path) {
            try? fileManager.createDirectory(at: bookDir, withIntermediateDirectories: true)
        }
        let filePath = bookDir.appendingPathComponent("\(chapterIndex).txt")
        try? content.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    public func saveConfig() {
        if let data = try? JSONEncoder().encode(readerConfig) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
}
