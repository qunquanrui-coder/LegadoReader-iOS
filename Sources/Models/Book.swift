import Foundation

public struct Book: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var author: String
    public var coverUrl: String?
    public var intro: String?
    public var latestChapter: String?
    public var sourceUrl: String
    public var sourceName: String
    public var bookUrl: String
    public var currentChapterIndex: Int
    public var currentChapterTitle: String?
    public var lastReadTime: Date
    public var totalChapters: Int
    
    public init(
        title: String,
        author: String,
        coverUrl: String? = nil,
        intro: String? = nil,
        latestChapter: String? = nil,
        sourceUrl: String,
        sourceName: String,
        bookUrl: String,
        currentChapterIndex: Int = 0,
        currentChapterTitle: String? = nil,
        lastReadTime: Date = Date(),
        totalChapters: Int = 0
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = "\(cleanTitle)_\(cleanAuthor)_\(bookUrl)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        self.title = cleanTitle
        self.author = cleanAuthor
        self.coverUrl = coverUrl
        self.intro = intro
        self.latestChapter = latestChapter
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.bookUrl = bookUrl
        self.currentChapterIndex = currentChapterIndex
        self.currentChapterTitle = currentChapterTitle
        self.lastReadTime = lastReadTime
        self.totalChapters = totalChapters
    }
}
