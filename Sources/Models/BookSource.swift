import Foundation

public struct LossyCodableList<Element: Decodable>: Decodable {
    public var elements: [Element]

    private struct ElementWrapper: Decodable {
        var element: Element?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.element = try? container.decode(Element.self)
        }
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let wrapper = try? container.decode(ElementWrapper.self), let element = wrapper.element {
                elements.append(element)
            } else {
                _ = try? container.decode(AnyCodableSkip.self)
            }
        }
        self.elements = elements
    }
}

private struct AnyCodableSkip: Decodable {}

public struct BookSource: Identifiable, Codable, Equatable, Hashable {
    public var id: String { bookSourceUrl }
    public var bookSourceName: String
    public var bookSourceUrl: String
    public var bookSourceType: Int?
    public var bookSourceComment: String?
    public var enabled: Bool?
    public var respondTime: Int?
    public var searchUrl: String?
    public var ruleSearch: RuleSearch?
    public var ruleBookInfo: RuleBookInfo?
    public var ruleToc: RuleToc?
    public var ruleContent: RuleContent?
    
    public init(
        bookSourceName: String,
        bookSourceUrl: String,
        bookSourceType: Int? = 0,
        bookSourceComment: String? = nil,
        enabled: Bool? = true,
        searchUrl: String? = nil,
        ruleSearch: RuleSearch? = nil,
        ruleBookInfo: RuleBookInfo? = nil,
        ruleToc: RuleToc? = nil,
        ruleContent: RuleContent? = nil
    ) {
        self.bookSourceName = bookSourceName
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceType = bookSourceType
        self.bookSourceComment = bookSourceComment
        self.enabled = enabled
        self.searchUrl = searchUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
    }
}

public struct RuleSearch: Codable, Equatable, Hashable {
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var coverUrl: String?
    public var bookUrl: String?
    public var lastChapter: String?
}

public struct RuleBookInfo: Codable, Equatable, Hashable {
    public var name: String?
    public var author: String?
    public var intro: String?
    public var coverUrl: String?
    public var lastChapter: String?
    public var tocUrl: String?
}

public struct RuleToc: Codable, Equatable, Hashable {
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
}

public struct RuleContent: Codable, Equatable, Hashable {
    public var content: String?
    public var nextContentUrl: String?
    public var replaceRegex: String?
}
