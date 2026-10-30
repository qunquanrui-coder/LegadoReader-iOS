import XCTest
import UIKit
@testable import LegadoReader

final class ReaderChapterLandingTests: XCTestCase {
    private let chapterURL = "https://fixture.invalid/book/chapter-4"

    private func pages(_ count: Int) -> [ReaderPage] {
        (0..<count).map { ReaderPage(items: [PaginatedParagraph(index: $0, text: "段落 \($0)")]) }
    }

    func testReverseSinglePageOpensLastPageAndConsumesIntentOnce() throws {
        var landing = ReaderChapterLanding()
        landing.requestEnd(chapterURL: chapterURL)
        let target = try XCTUnwrap(landing.consume(chapterURL: chapterURL,
            paragraphs: (0..<5).map { "段落 \($0)" }, pages: pages(5), presentation: .page, viewportReady: true))
        XCTAssertEqual(target.pageIndex, 4)
        XCTAssertEqual(target.anchor, ReaderTextAnchor(chapterURL: chapterURL, paragraphIndex: 4))
        XCTAssertNil(landing.pendingChapterURL)
        XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: ["新布局"], pages: pages(1),
                                     presentation: .page, viewportReady: true))
    }

    func testEvenSpreadOpensBothLastPagesAndOddSpreadOpensLastSinglePage() throws {
        for (count, expectedPage, expectedSpread) in [(4, 2, 1), (5, 4, 2), (1, 0, 0)] {
            var landing = ReaderChapterLanding()
            landing.requestEnd(chapterURL: chapterURL)
            let target = try XCTUnwrap(landing.consume(chapterURL: chapterURL,
                paragraphs: (0..<count).map { "段落 \($0)" }, pages: pages(count),
                presentation: .spread, viewportReady: true))
            XCTAssertEqual(target.pageIndex, expectedPage)
            XCTAssertEqual(target.spreadIndex, expectedSpread)
            XCTAssertEqual(target.anchor.paragraphIndex, expectedPage)
        }
    }

    func testScrollFallbackOpensLastParagraphWithoutDependingOnPages() throws {
        var landing = ReaderChapterLanding()
        landing.requestEnd(chapterURL: chapterURL)
        let target = try XCTUnwrap(landing.consume(chapterURL: chapterURL, paragraphs: ["首段", "中段", "尾段"],
            pages: [], presentation: .scroll, viewportReady: true))
        XCTAssertEqual(target.anchor.paragraphIndex, 2)
        XCTAssertEqual(target.anchor.characterOffset, 0)
    }

    func testUnmeasuredLayoutAndEmptyContentRetainPendingDestination() throws {
        var landing = ReaderChapterLanding()
        landing.requestEnd(chapterURL: chapterURL)
        XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: ["正文"], pages: pages(3),
                                     presentation: .spread, viewportReady: false))
        XCTAssertEqual(landing.pendingChapterURL, chapterURL)
        XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: ["正文"], pages: [],
                                     presentation: .page, viewportReady: true))
        XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: [], pages: [],
                                     presentation: .scroll, viewportReady: true))
        XCTAssertEqual(landing.pendingChapterURL, chapterURL)
        let target = try XCTUnwrap(landing.consume(chapterURL: chapterURL, paragraphs: ["正文"], pages: pages(1),
                                                 presentation: .page, viewportReady: true))
        XCTAssertEqual(target.pageIndex, 0)
    }

    func testOldLoadsCannotConsumeAReplacementOrCancelledRequest() throws {
        let replacement = "https://fixture.invalid/book/chapter-2"
        var landing = ReaderChapterLanding()
        landing.requestEnd(chapterURL: chapterURL)
        landing.requestEnd(chapterURL: replacement)
        XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: ["旧章"], pages: pages(1),
                                     presentation: .page, viewportReady: true))
        XCTAssertEqual(landing.pendingChapterURL, replacement)
        XCTAssertNotNil(landing.consume(chapterURL: replacement, paragraphs: ["新章"], pages: pages(1),
                                        presentation: .page, viewportReady: true))
        landing.requestEnd(chapterURL: chapterURL)
        landing.cancel()
        XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: ["正文"], pages: pages(1),
                                     presentation: .page, viewportReady: true))
    }

    func testTitleOnlyChapterHasAnEndPage() throws {
        for presentation in [ReaderPresentation.page, .spread] {
            var landing = ReaderChapterLanding()
            landing.requestEnd(chapterURL: chapterURL)
            let titlePage = ReaderPage(items: [], title: "只有标题的章节")
            let target = try XCTUnwrap(landing.consume(chapterURL: chapterURL, paragraphs: [], pages: [titlePage],
                                                     presentation: presentation, viewportReady: true))
            XCTAssertEqual(target.pageIndex, 0)
            XCTAssertEqual(target.anchor.paragraphIndex, 0)
        }
    }

    @MainActor
    func testLongParagraphLandsOnFinalFragmentAndAnchorSurvivesReflow() throws {
        let paragraph = String(repeating: "反向翻章必须抵达正文末尾，而不是再次回到本章开始。👩🏽‍💻 ", count: 90)
        let style = ReaderPageStyle(config: .default)
        let pages = ReaderPaginator.paginate(paragraphs: [paragraph], chapterTitle: "第四章",
                                             style: style, viewport: CGSize(width: 280, height: 330))
        XCTAssertGreaterThan(pages.count, 3)
        for presentation in [ReaderPresentation.page, .spread] {
            var landing = ReaderChapterLanding()
            landing.requestEnd(chapterURL: chapterURL)
            let target = try XCTUnwrap(landing.consume(chapterURL: chapterURL, paragraphs: [paragraph], pages: pages,
                                                     presentation: presentation, viewportReady: true))
            let expectedPage = presentation == .spread ? ((pages.count - 1) / 2) * 2 : pages.count - 1
            let first = try XCTUnwrap(pages[expectedPage].items.first)
            XCTAssertEqual(target.anchor.characterOffset, first.characterOffset)
            XCTAssertGreaterThan(target.anchor.characterOffset, 0)
            XCTAssertEqual(ReaderPageLocator.pageIndex(paragraphIndex: target.anchor.paragraphIndex,
                characterOffset: target.anchor.characterOffset, pages: pages), expectedPage)

            let reflowed = ReaderPaginator.paginate(paragraphs: [paragraph], chapterTitle: "第四章",
                style: style, viewport: CGSize(width: 350, height: 430))
            let restoredPage = ReaderPageLocator.pageIndex(paragraphIndex: target.anchor.paragraphIndex,
                characterOffset: target.anchor.characterOffset, pages: reflowed)
            let fragment = try XCTUnwrap(reflowed[restoredPage].items.first)
            XCTAssertLessThanOrEqual(fragment.characterOffset, target.anchor.characterOffset)
            XCTAssertGreaterThan(fragment.characterOffset + fragment.text.utf16.count,
                                 target.anchor.characterOffset)
            XCTAssertNil(landing.consume(chapterURL: chapterURL, paragraphs: [paragraph], pages: reflowed,
                                         presentation: presentation, viewportReady: true))
        }
    }
}
