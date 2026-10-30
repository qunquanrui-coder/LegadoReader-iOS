import Foundation
import CoreGraphics

public enum ReaderPresentation: String, Equatable {
    case scroll, page, spread
}

/// Layout depends on this window's safe reading area, never a device name or pixel resolution.
public enum ReaderLayoutPolicy {
    public static func presentation(size: CGSize, preferred: ReaderPageTurnMode,
                                    autoSpread: Bool, fontSize: CGFloat, spineWidth: CGFloat) -> ReaderPresentation {
        let minimumColumn = max(250, fontSize * 11 + 36)
        let canSpread = size.width >= minimumColumn * 2 + spineWidth && size.height >= 260
        if canSpread && (preferred == .duoSpread || autoSpread) { return .spread }
        if preferred == .horizontalSlide || preferred == .duoSpread {
            return size.width >= 180 && size.height >= max(150, fontSize * 5) ? .page : .scroll
        }
        return .scroll
    }

    public static func sidebarWidth(availableWidth: CGFloat) -> CGFloat {
        min(280, max(180, availableWidth * 0.3))
    }
}

public struct ReaderTextAnchor: Equatable {
    public var chapterURL: String
    public var paragraphIndex: Int
    public var characterOffset: Int

    public init(chapterURL: String, paragraphIndex: Int, characterOffset: Int = 0) {
        self.chapterURL = chapterURL
        self.paragraphIndex = max(0, paragraphIndex)
        self.characterOffset = max(0, characterOffset)
    }
}

public enum ReaderPageLocator {
    public static func pageIndex(paragraphIndex: Int, characterOffset: Int, pages: [ReaderPage]) -> Int {
        guard !pages.isEmpty else { return 0 }
        // A title-only opening page must remain visible when opening a chapter at its start.
        if paragraphIndex == 0 && characterOffset == 0 && pages[0].title != nil { return 0 }
        var selected: Int?
        for (index, page) in pages.enumerated() {
            for item in page.items where item.index == paragraphIndex && item.characterOffset <= characterOffset {
                selected = index
            }
        }
        return selected ?? pages.firstIndex { $0.items.contains { $0.index >= paragraphIndex } } ?? (pages.count - 1)
    }
}

/// Ignore callbacks from the old layout until the same chapter has been positioned in the new one.
public struct ReaderLayoutRestoration {
    public private(set) var token = UUID()
    public private(set) var anchor: ReaderTextAnchor?

    public init() {}

    @discardableResult
    public mutating func begin(_ anchor: ReaderTextAnchor) -> UUID {
        token = UUID()
        self.anchor = anchor
        return token
    }

    public func accepts(_ token: UUID, chapterURL: String?) -> Bool {
        self.token == token && anchor?.chapterURL == chapterURL
    }

    public mutating func finish(_ token: UUID, chapterURL: String?, liveParagraphIndex: Int? = nil) -> ReaderTextAnchor? {
        guard accepts(token, chapterURL: chapterURL) else { return nil }
        var restored = anchor
        if let liveParagraphIndex = liveParagraphIndex {
            restored?.paragraphIndex = max(0, liveParagraphIndex)
            restored?.characterOffset = 0
        }
        anchor = nil
        return restored
    }

    public mutating func cancel() { token = UUID(); anchor = nil }
}
