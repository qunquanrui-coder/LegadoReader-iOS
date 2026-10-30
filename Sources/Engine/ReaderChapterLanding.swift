import Foundation

/// A manual reverse page turn has a different destination from selecting a chapter in the TOC.
/// Keep the intent until the requested chapter has both content and its final viewport layout.
public struct ReaderChapterLanding {
    public private(set) var pendingChapterURL: String?

    public init() {}

    public mutating func requestEnd(chapterURL: String) {
        pendingChapterURL = chapterURL.isEmpty ? nil : chapterURL
    }

    public mutating func cancel() { pendingChapterURL = nil }

    /// A stale load or an unmeasured viewport cannot consume the current chapter's destination.
    /// Once consumed, later reflows use the returned text anchor instead of jumping to the end again.
    public mutating func consume(chapterURL: String, paragraphs: [String], pages: [ReaderPage],
                                 presentation: ReaderPresentation, viewportReady: Bool) -> ReaderChapterLandingTarget? {
        guard pendingChapterURL == chapterURL, viewportReady else { return nil }

        let pageIndex: Int
        let paragraphIndex: Int
        let characterOffset: Int
        switch presentation {
        case .scroll:
            guard !paragraphs.isEmpty else { return nil }
            pageIndex = 0
            paragraphIndex = paragraphs.count - 1
            characterOffset = 0
        case .page, .spread:
            guard !pages.isEmpty else { return nil }
            pageIndex = presentation == .spread ? ((pages.count - 1) / 2) * 2 : pages.count - 1
            let groupEnd = min(pages.count, pageIndex + (presentation == .spread ? 2 : 1))
            let first = pages[pageIndex..<groupEnd].lazy.flatMap(\.items).first
            if let first {
                paragraphIndex = first.index
                characterOffset = first.characterOffset
            } else if paragraphs.isEmpty, pages[pageIndex..<groupEnd].contains(where: { $0.title != nil }) {
                // A chapter containing only its title still has a valid opening/end page.
                paragraphIndex = 0
                characterOffset = 0
            } else {
                return nil
            }
        }

        pendingChapterURL = nil
        return ReaderChapterLandingTarget(
            anchor: ReaderTextAnchor(chapterURL: chapterURL, paragraphIndex: paragraphIndex,
                                     characterOffset: characterOffset),
            pageIndex: pageIndex, spreadIndex: pageIndex / 2)
    }
}

public struct ReaderChapterLandingTarget: Equatable {
    public let anchor: ReaderTextAnchor
    public let pageIndex: Int
    public let spreadIndex: Int
}
