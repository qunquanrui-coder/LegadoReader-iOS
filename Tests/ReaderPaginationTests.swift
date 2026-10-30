import XCTest
import UIKit
@testable import LegadoReader

final class ReaderPaginationTests: XCTestCase {
    private func config(fontSize: CGFloat = 19, design: ReaderFontDesign = .serif,
                        spacing: CGFloat = 10) -> ReaderConfig {
        var value = ReaderConfig.default
        value.fontSize = fontSize
        value.fontDesign = design
        value.lineSpacing = spacing
        return value
    }

    private func assertComplete(_ paragraphs: [String], pages: [ReaderPage], style: ReaderPageStyle,
                                viewport: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(pages.isEmpty, file: file, line: line)
        let allItems = pages.flatMap(\.items)
        XCTAssertEqual(Set(allItems.map(\.id)).count, allItems.count, file: file, line: line)
        for (index, paragraph) in paragraphs.enumerated() {
            let fragments = allItems.filter { $0.index == index }
            XCTAssertEqual(fragments.map(\.text).joined(), paragraph, file: file, line: line)
            let boundaries = Set(paragraph.indices.map { $0.utf16Offset(in: paragraph) } + [paragraph.utf16.count])
            var nextOffset = 0
            for fragment in fragments {
                XCTAssertEqual(fragment.characterOffset, nextOffset, file: file, line: line)
                XCTAssertTrue(boundaries.contains(fragment.characterOffset), file: file, line: line)
                nextOffset += fragment.text.utf16.count
                XCTAssertTrue(boundaries.contains(nextOffset), file: file, line: line)
            }
        }
        let width = style.contentWidth(in: viewport)
        for page in pages {
            XCTAssertLessThanOrEqual(style.contentHeight(of: page, width: width),
                                     viewport.height - 2 * style.verticalInset, file: file, line: line)
            for item in page.items {
                let size = style.measuredSize(of: style.attributedBody(item.text), width: width)
                XCTAssertLessThanOrEqual(size.width, width, file: file, line: line)
            }
        }
        XCTAssertTrue(pages.dropFirst().allSatisfy { $0.title == nil }, file: file, line: line)
    }

    @MainActor
    func testNarrowAndWidePagesPreserveEveryParagraphAcrossFontDesigns() {
        let paragraphs = [
            "　　第一段很短。",
            String(repeating: "正文测量需要与实际显示的字体和间距相同。", count: 30),
            String(repeating: "A long paragraph must wrap and continue on the following page. ", count: 15),
            "最后一段，必须完整保留。"
        ]
        for design in ReaderFontDesign.allCases {
            let style = ReaderPageStyle(config: config(design: design))
            let widths: [CGFloat] = [220, 330, 430]
            for width in widths {
                let viewport = CGSize(width: width, height: 420)
                let pages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "第一章 测量与显示",
                                                      style: style, viewport: viewport)
                assertComplete(paragraphs, pages: pages, style: style, viewport: viewport)
                XCTAssertEqual(pages.first?.title, "第一章 测量与显示")
                XCTAssertGreaterThan(pages.count, 1)
            }
        }
    }

    @MainActor
    func testFractionalColumnWidthsKeepFittingTextWithoutRoundingItOutOfThePage() {
        let style = ReaderPageStyle(config: config(fontSize: 19, design: .system, spacing: 4))
        // An unwrapped line with a fractional glyph width must stay one page when the
        // content width is exactly its measured width (rounding up used to reject it).
        let paragraph = "Fractional widths: iii WWW 123."
        let attributed = style.attributedBody(paragraph)
        let rendered = UITextView(frame: CGRect(x: 0, y: 0, width: 1000, height: 100))
        rendered.isScrollEnabled = false
        rendered.textContainerInset = .zero
        rendered.textContainer.lineFragmentPadding = 0
        rendered.attributedText = attributed
        rendered.layoutManager.ensureLayout(for: rendered.textContainer)
        let renderedWidth = rendered.layoutManager.usedRect(for: rendered.textContainer).width
        let measured = style.measuredSize(of: attributed, width: 1000)
        XCTAssertGreaterThan(renderedWidth, 0)
        XCTAssertEqual(measured.width, renderedWidth, accuracy: 0.001)
        let viewport = CGSize(width: renderedWidth + 0.01 + 2 * style.horizontalInset,
                              height: measured.height + 2 * style.verticalInset + 1)
        let pages = ReaderPaginator.paginate(paragraphs: [paragraph], chapterTitle: "",
                                             style: style, viewport: viewport)
        assertComplete([paragraph], pages: pages, style: style, viewport: viewport)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.items.first?.text, paragraph)

        let longParagraph = String(repeating: "Fractional Duo columns should fill naturally. 中文也要完整。", count: 35)
        let widths: [CGFloat] = [333.5, 444.5]
        for width in widths {
            let fractionalViewport = CGSize(width: width, height: 420)
            let splitPages = ReaderPaginator.paginate(paragraphs: [longParagraph], chapterTitle: "",
                                                      style: style, viewport: fractionalViewport)
            assertComplete([longParagraph], pages: splitPages, style: style, viewport: fractionalViewport)
        }
    }

    @MainActor
    func testLongParagraphSplitsOnGraphemeBoundariesWithContinuousUTF16Offsets() {
        let paragraph = String(repeating: "家人👨‍👩‍👧‍👦，旗帜🇨🇳，组合字e\u{301}与表情👩🏽‍💻。", count: 45)
        let style = ReaderPageStyle(config: config(fontSize: 26, design: .rounded, spacing: 14))
        let viewport = CGSize(width: 235, height: 300)
        let pages = ReaderPaginator.paginate(paragraphs: [paragraph], chapterTitle: "",
                                             style: style, viewport: viewport)
        assertComplete([paragraph], pages: pages, style: style, viewport: viewport)
        XCTAssertGreaterThan(pages.count, 3)
        XCTAssertTrue(pages.flatMap(\.items).dropFirst().allSatisfy { $0.characterOffset > 0 })
    }

    @MainActor
    func testLargerTextAndNarrowerViewportProduceMorePagesWithoutDroppingText() {
        let paragraphs = [String(repeating: "可读宽度改变后，需要重新分页并保留全文。", count: 100)]
        let small = ReaderPageStyle(config: config(fontSize: 16, design: .system, spacing: 4))
        let large = ReaderPageStyle(config: config(fontSize: 30, design: .system, spacing: 16))
        let viewport = CGSize(width: 380, height: 500)
        let smallPages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "", style: small, viewport: viewport)
        let largePages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "", style: large, viewport: viewport)
        assertComplete(paragraphs, pages: smallPages, style: small, viewport: viewport)
        assertComplete(paragraphs, pages: largePages, style: large, viewport: viewport)
        XCTAssertGreaterThan(largePages.count, smallPages.count)
        let narrowViewport = CGSize(width: 200, height: viewport.height)
        let narrowPages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "", style: small, viewport: narrowViewport)
        assertComplete(paragraphs, pages: narrowPages, style: small, viewport: narrowViewport)
        XCTAssertGreaterThan(narrowPages.count, smallPages.count)
    }

    @MainActor
    func testTitleCanOccupyFirstPageWithoutLosingFirstBodyParagraph() {
        let style = ReaderPageStyle(config: config())
        let title = "第一章 单独的标题"
        let width: CGFloat = 300
        let titleHeight = style.measuredHeight(of: style.attributedTitle(title), width: width - 2 * style.horizontalInset)
        let viewport = CGSize(width: width, height: titleHeight + 2 * style.verticalInset + style.bodyFont.lineHeight / 2)
        let paragraphs = ["章节正文依然必须出现在下一页。"]
        let pages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: title, style: style, viewport: viewport)
        assertComplete(paragraphs, pages: pages, style: style, viewport: viewport)
        XCTAssertEqual(pages.first?.title, title)
        XCTAssertEqual(pages.first?.items, [])
        XCTAssertGreaterThanOrEqual(pages.count, 2)
    }

    @MainActor
    func testTinyOrInvalidViewportsRequestScrollingFallbackInsteadOfClippedPages() {
        let style = ReaderPageStyle(config: config())
        let paragraphs = ["不能通过伪造最小宽度来把正文挤出窗口。"]
        for viewport in [CGSize(width: 20, height: 400), CGSize(width: 300, height: 10),
                         CGSize.zero, CGSize(width: CGFloat.nan, height: 400)] {
            XCTAssertTrue(ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "",
                                                   style: style, viewport: viewport).isEmpty)
        }
        let longTitle = String(repeating: "标题", count: 300)
        XCTAssertTrue(ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: longTitle,
                                               style: style, viewport: CGSize(width: 200, height: 300)).isEmpty)
    }

    @MainActor
    func testSharedMetricsMatchZeroInsetTextViewRendering() {
        for design in ReaderFontDesign.allCases {
            let style = ReaderPageStyle(config: config(design: design))
            for value in ["中文和 English 混合排版。", "第一行\n第二行\n", "👨‍👩‍👧‍👦 与组合字 e\u{301}"] {
                let attributed = style.attributedBody(value)
                let width: CGFloat = 240
                let view = UITextView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
                view.isScrollEnabled = false
                view.textContainerInset = .zero
                view.textContainer.lineFragmentPadding = 0
                view.layoutManager.usesFontLeading = true
                view.attributedText = attributed
                let renderedHeight = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
                XCTAssertEqual(style.measuredHeight(of: attributed, width: width), ceil(renderedHeight), accuracy: 1)
                XCTAssertEqual((attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontDescriptor,
                               style.bodyFont.fontDescriptor)
            }
        }
    }
}
