import Foundation
import UIKit

/// A paragraph may span pages. The offset keeps its fragments distinct without changing
/// the paragraph index used by reading progress and speech playback.
public struct PaginatedParagraph: Identifiable, Equatable {
    public var id: String { "\(index):\(characterOffset)" }
    public let index: Int
    public let text: String
    public let characterOffset: Int

    public init(index: Int, text: String, characterOffset: Int = 0) {
        self.index = index
        self.text = text
        self.characterOffset = characterOffset
    }
}

public struct ReaderPage: Equatable {
    public let items: [PaginatedParagraph]
    public let title: String?

    public init(items: [PaginatedParagraph], title: String? = nil) {
        self.items = items
        self.title = title
    }
}

/// The renderer and paginator share fonts, paragraph styles and insets. Measurements
/// use TextKit with the same zero text-container padding as the reader's text views.
public struct ReaderPageStyle {
    public let bodyFont: UIFont
    public let titleFont: UIFont
    public let lineSpacing: CGFloat
    public let paragraphSpacing: CGFloat
    public let horizontalInset: CGFloat = 18
    public let verticalInset: CGFloat = 8

    public init(config: ReaderConfig) {
        let fontSize = config.fontSize.isFinite ? min(80, max(8, config.fontSize)) : 19
        lineSpacing = config.lineSpacing.isFinite ? min(80, max(0, config.lineSpacing)) : 10
        paragraphSpacing = lineSpacing + 11
        let design: UIFontDescriptor.SystemDesign
        switch config.fontDesign {
        case .serif: design = .serif
        case .system: design = .default
        case .rounded: design = .rounded
        }
        let body = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let title = UIFont.systemFont(ofSize: fontSize + 3, weight: .bold)
        bodyFont = UIFont(descriptor: body.fontDescriptor.withDesign(design) ?? body.fontDescriptor, size: fontSize)
        titleFont = UIFont(descriptor: title.fontDescriptor.withDesign(design) ?? title.fontDescriptor, size: fontSize + 3)
    }

    public init(_ config: ReaderConfig) { self.init(config: config) }

    public func attributedBody(_ text: String) -> NSAttributedString {
        attributed(text, font: bodyFont)
    }

    public func attributedTitle(_ text: String) -> NSAttributedString {
        attributed(text, font: titleFont)
    }

    private func attributed(_ text: String, font: UIFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
    }

    public func contentWidth(in viewport: CGSize) -> CGFloat {
        max(0, viewport.width - 2 * horizontalInset)
    }

    /// Height of TextKit's complete layout, including a final blank line after a newline.
    /// The renderer must use textContainerInset = .zero and lineFragmentPadding = 0.
    public func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        measuredSize(of: text, width: width).height
    }

    public func measuredSize(of text: NSAttributedString, width: CGFloat) -> CGSize {
        guard text.length > 0, width.isFinite, width > 0 else { return .zero }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        manager.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentUsedRect
        return CGSize(width: ceil(max(used.maxX, extra.maxX)),
                      height: ceil(max(used.maxY, extra.maxY)))
    }

    /// Used for both layout assertions and the renderer's content-height calculation.
    public func contentHeight(of page: ReaderPage, width: CGFloat) -> CGFloat {
        var heights: [CGFloat] = []
        if let title = page.title, !title.isEmpty {
            heights.append(measuredHeight(of: attributedTitle(title), width: width))
        }
        heights.append(contentsOf: page.items.map { measuredHeight(of: attributedBody($0.text), width: width) })
        return heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * paragraphSpacing
    }
}

public enum ReaderPaginator {
    /// Returns no pages when the viewport cannot fit even a single complete glyph/line
    /// or the title. The caller can then show the ordinary scrolling reader rather than
    /// fabricate a minimum page width or silently clip text in a tiny split-view window.
    public static func paginate(paragraphs: [String], chapterTitle: String,
                                style: ReaderPageStyle, viewport: CGSize) -> [ReaderPage] {
        guard viewport.width.isFinite, viewport.height.isFinite else { return [] }
        let width = style.contentWidth(in: viewport)
        let height = viewport.height - 2 * style.verticalInset
        guard width > 0, height >= ceil(style.bodyFont.lineHeight) else { return [] }

        var title: String? = chapterTitle.isEmpty ? nil : chapterTitle
        var titleHeight: CGFloat = 0
        if let title = title {
            let size = style.measuredSize(of: style.attributedTitle(title), width: width)
            guard size.width <= width, size.height <= height else { return [] }
            titleHeight = size.height
        }

        var pages: [ReaderPage] = []
        var items: [PaginatedParagraph] = []
        var usedHeight = titleHeight

        func flushPage() {
            if title != nil || !items.isEmpty {
                pages.append(ReaderPage(items: items, title: title))
            }
            items = []
            title = nil
            usedHeight = 0
        }

        for (index, paragraph) in paragraphs.enumerated() where !paragraph.isEmpty {
            var remaining = paragraph[...]
            var offset = 0
            while !remaining.isEmpty {
                let hasContent = title != nil || !items.isEmpty
                let gap = hasContent ? style.paragraphSpacing : 0
                let availableHeight = height - usedHeight - gap
                let prefix = fittingPrefix(of: remaining, style: style, width: width, height: availableHeight)
                guard !prefix.isEmpty else {
                    if hasContent { flushPage(); continue }
                    // No character can be displayed at this size. Let the caller fall back
                    // to a scrolling layout, preserving the entire original text.
                    return []
                }
                let text = String(prefix)
                items.append(PaginatedParagraph(index: index, text: text, characterOffset: offset))
                usedHeight += gap + style.measuredHeight(of: style.attributedBody(text), width: width)
                offset += text.utf16.count
                remaining = remaining[prefix.endIndex...]
                if !remaining.isEmpty { flushPage() }
            }
        }
        flushPage()
        return pages
    }

    /// Binary search over extended grapheme boundaries: emoji, combining marks and
    /// surrogate pairs stay intact, and every original UTF-16 code unit is retained.
    private static func fittingPrefix(of text: Substring, style: ReaderPageStyle,
                                      width: CGFloat, height: CGFloat) -> Substring {
        guard height >= ceil(style.bodyFont.lineHeight) else { return text.prefix(0) }
        func fits(_ end: String.Index) -> Bool {
            let value = String(text[..<end])
            let size = style.measuredSize(of: style.attributedBody(value), width: width)
            return size.height <= height && size.width <= width
        }
        if fits(text.endIndex) { return text }
        let boundaries = Array(text.indices.dropFirst()) + [text.endIndex]
        var lower = 0
        var upper = boundaries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if fits(boundaries[middle]) { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower > 0 else { return text.prefix(0) }
        return text[..<boundaries[lower - 1]]
    }
}
