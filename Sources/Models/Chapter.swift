import Foundation

public struct Chapter: Identifiable, Codable, Equatable, Hashable {
    public var id: String { "\(index)_\(url)" }
    public var index: Int
    public var title: String
    public var url: String
    public var isCached: Bool
    
    public init(index: Int, title: String, url: String, isCached: Bool = false) {
        self.index = index
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
        self.isCached = isCached
    }
}
