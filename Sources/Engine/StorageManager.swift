import Foundation
import Combine

public class StorageManager: ObservableObject {
    public static let shared = StorageManager()
    
    @Published public var bookshelf: [Book] = []
    @Published public var bookSources: [BookSource] = []
    @Published public var readerConfig: ReaderConfig = .default
    
    private let bookshelfKey = "LegadoReader_Bookshelf"
    private let sourcesKey = "LegadoReader_BookSources"
    private let configKey = "LegadoReader_ReaderConfig"
    
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
        }
        
        if let sourcesData = UserDefaults.standard.data(forKey: sourcesKey),
           let savedSources = try? JSONDecoder().decode([BookSource].self, from: sourcesData),
           !savedSources.isEmpty {
            self.bookSources = savedSources
        } else {
            loadDefaultSources()
        }
    }
    
    // MARK: - BookShelf Operations
    public func addBookToShelf(_ book: Book) {
        if !bookshelf.contains(where: { $0.id == book.id }) {
            bookshelf.insert(book, at: 0)
            saveBookshelf()
        }
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
        
        var existingMap = Dictionary(uniqueKeysWithValues: bookSources.map { ($0.bookSourceUrl, $0) })
        var addedCount = 0
        
        for s in newSources {
            guard !s.bookSourceUrl.isEmpty, !s.bookSourceName.isEmpty else { continue }
            if existingMap[s.bookSourceUrl] == nil {
                addedCount += 1
            }
            existingMap[s.bookSourceUrl] = s
        }
        
        bookSources = Array(existingMap.values).sorted { $0.bookSourceName < $1.bookSourceName }
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
