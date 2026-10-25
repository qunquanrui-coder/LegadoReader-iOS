import Foundation

/// Identity tokens for in-flight chapter / catalogue loads.
///
/// Starting a new load replaces its token, and leaving the reader invalidates every token,
/// so a completion that arrives late can prove it is still current before it is allowed to
/// touch shared reading progress, cached TOC or the speech context.
public struct LoadTokenSet: Equatable {
    public private(set) var chapterLoadID: UUID
    public private(set) var tocLoadID: UUID

    public init(chapterLoadID: UUID = UUID(), tocLoadID: UUID = UUID()) {
        self.chapterLoadID = chapterLoadID
        self.tocLoadID = tocLoadID
    }

    /// Starts a chapter-content load and returns its identity.
    @discardableResult
    public mutating func beginChapterLoad() -> UUID {
        chapterLoadID = UUID()
        return chapterLoadID
    }

    /// Starts a catalogue load and returns its identity.
    @discardableResult
    public mutating func beginTocLoad() -> UUID {
        tocLoadID = UUID()
        return tocLoadID
    }

    /// Invalidates every in-flight request, e.g. when the reader page is dismissed.
    public mutating func invalidateAll() {
        chapterLoadID = UUID()
        tocLoadID = UUID()
    }

    public func isCurrentChapterLoad(_ id: UUID) -> Bool { id == chapterLoadID }
    public func isCurrentTocLoad(_ id: UUID) -> Bool { id == tocLoadID }
}
