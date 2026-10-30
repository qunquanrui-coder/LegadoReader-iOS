import Foundation

public struct Book: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    /// Search rows distinguish source variants without changing the persisted shelf/cache identity.
    public var searchResultID: String { sourceUrl + "\n" + bookUrl }
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
    public var currentParagraphIndex: Int?
    public var currentCharacterOffset: Int?
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
        currentParagraphIndex: Int? = 0,
        currentCharacterOffset: Int? = 0,
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
        self.currentParagraphIndex = currentParagraphIndex
        self.currentCharacterOffset = max(0, currentCharacterOffset ?? 0)
        self.lastReadTime = lastReadTime
        self.totalChapters = totalChapters
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, coverUrl, intro, latestChapter, sourceUrl, sourceName, bookUrl
        case currentChapterIndex, currentChapterTitle, currentParagraphIndex, currentCharacterOffset
        case lastReadTime, totalChapters
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        author = try values.decode(String.self, forKey: .author)
        coverUrl = try values.decodeIfPresent(String.self, forKey: .coverUrl)
        intro = try values.decodeIfPresent(String.self, forKey: .intro)
        latestChapter = try values.decodeIfPresent(String.self, forKey: .latestChapter)
        sourceUrl = try values.decode(String.self, forKey: .sourceUrl)
        sourceName = try values.decode(String.self, forKey: .sourceName)
        bookUrl = try values.decode(String.self, forKey: .bookUrl)
        currentChapterIndex = try values.decode(Int.self, forKey: .currentChapterIndex)
        currentChapterTitle = try values.decodeIfPresent(String.self, forKey: .currentChapterTitle)
        currentParagraphIndex = try values.decodeIfPresent(Int.self, forKey: .currentParagraphIndex)
        currentCharacterOffset = max(0, try values.decodeIfPresent(Int.self, forKey: .currentCharacterOffset) ?? 0)
        lastReadTime = try values.decode(Date.self, forKey: .lastReadTime)
        totalChapters = try values.decode(Int.self, forKey: .totalChapters)
    }
}
