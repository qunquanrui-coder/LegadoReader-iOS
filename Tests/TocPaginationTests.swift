import XCTest
@testable import LegadoReader

private actor TocFixturePages {
    private let pages: [String: String]
    private(set) var requested: [String] = []

    init(_ pages: [String: String]) { self.pages = pages }

    func fetch(_ url: String, referer: String?) throws -> (String, URL) {
        requested.append(url)
        guard let html = pages[url], let parsedURL = URL(string: url) else { throw URLError(.timedOut) }
        return (html, parsedURL)
    }
}

final class TocPaginationTests: XCTestCase {
    private let firstPage = "https://fixture.invalid/book/1.html"
    private let secondPage = "https://fixture.invalid/book/1_2.html"
    private let thirdPage = "https://fixture.invalid/book/1_3.html"

    private func source(nextRule: String? = "a.next@href") -> BookSource {
        BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://fixture.invalid",
                   ruleToc: RuleToc(chapterList: "#list a", chapterName: "text",
                                    chapterUrl: "href", nextTocUrl: nextRule))
    }

    private func tocPage(_ chapters: [(String, String)], next: String? = nil, nextRel: String? = nil) -> String {
        var html = "<html><body><div id='list'>"
        for (title, href) in chapters {
            html += "<a href='\(href)'>\(title)</a>"
        }
        html += "</div>"
        if let next {
            html += "<a class='next' href='\(next)'>下一页</a>"
        }
        if let nextRel {
            html += "<link rel='next' href='\(nextRel)'>"
        }
        html += "</body></html>"
        return html
    }

    private func chapters(_ start: Int, count: Int = 3) -> [(String, String)] {
        (start..<(start + count)).map { idx in
            ("第\(idx)章 测试", "https://fixture.invalid/c/\(idx).html")
        }
    }

    func testFollowsEveryNextPageAndReindexes() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), next: secondPage),
            secondPage: tocPage(chapters(4), next: thirdPage),
            thirdPage: tocPage(chapters(7))
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.pagesFetched, 3)
        XCTAssertEqual(result.chapters.count, 9)
        XCTAssertEqual(result.chapters.map(\.index), Array(0..<9))
        XCTAssertEqual(Set(result.chapters.map(\.url)).count, 9)
        let requested = await fixture.requested
        XCTAssertEqual(requested, [firstPage, secondPage, thirdPage])
    }

    func testRepeatedPageURLIsNotFetchedTwice() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), next: firstPage)
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.chapters.count, 3)
        let requested = await fixture.requested
        XCTAssertEqual(requested, [firstPage])
    }

    func testPageAddingNoNewChaptersStopsPagination() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), next: secondPage),
            secondPage: tocPage(chapters(1), next: thirdPage)
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.chapters.count, 3)
        let requested = await fixture.requested
        XCTAssertEqual(requested, [firstPage, secondPage])
    }

    func testPageLimitMarksResultIncomplete() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), next: secondPage),
            secondPage: tocPage(chapters(4), next: thirdPage),
            thirdPage: tocPage(chapters(7))
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 2,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.pagesFetched, 2)
        XCTAssertEqual(result.chapters.count, 6)
        let requested = await fixture.requested
        XCTAssertEqual(requested, [firstPage, secondPage])
    }

    func testFailureOnLaterPageKeepsCollectedChaptersButReportsIncomplete() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), next: secondPage)
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.chapters.count, 3)
        XCTAssertNotNil(result.lastErrorDescription)
    }

    func testSinglePageTocIsComplete() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1))
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.pagesFetched, 1)
        XCTAssertEqual(result.chapters.count, 3)
    }

    func testRelNextIsFollowedWithoutNextTocRule() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), nextRel: secondPage),
            secondPage: tocPage(chapters(4))
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(nextRule: nil), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.chapters.count, 6)
        let requested = await fixture.requested
        XCTAssertEqual(requested, [firstPage, secondPage])
    }

    func testDuplicateChapterOnNextPageIsIgnoredOnce() async throws {
        let fixture = TocFixturePages([
            firstPage: tocPage(chapters(1), next: secondPage),
            secondPage: tocPage([
                ("第3章 测试", "https://fixture.invalid/c/3.html"),
                ("第4章 测试", "https://fixture.invalid/c/4.html")
            ])
        ])
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: firstPage, source: source(), maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.chapters.count, 4)
        XCTAssertEqual(result.chapters.map(\.index), Array(0..<4))
        XCTAssertEqual(result.chapters.filter { $0.url.hasSuffix("/3.html") }.count, 1)
    }

    func testDeclaredSeparateTocFailureKeepsBookPageFallbackIncomplete() async throws {
        let bookPage = "https://fixture.invalid/book/1.html"
        let previewChapters = (1...5).map {
            "<a href='https://fixture.invalid/c/\($0).html'>第\($0)章 预览</a>"
        }.joined()
        let bookHtml = "<html><body><a class='toc' href='https://fixture.invalid/book/1/toc'>目录</a>"
            + "<div id='latest'>\(previewChapters)</div></body></html>"
        // The declared TOC page is not in the fixture, so the fetch fails and only the
        // book-info preview (latest 5 chapters) is available.
        let fixture = TocFixturePages([bookPage: bookHtml])
        let source = BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://fixture.invalid",
                                ruleBookInfo: RuleBookInfo(name: nil, author: nil, intro: nil,
                                                           coverUrl: nil, latestChapter: nil,
                                                           tocUrl: "a.toc@href"),
                                ruleToc: RuleToc(chapterList: "#latest a", chapterName: "text", chapterUrl: "href"))
        let result = try await LegadoParser.shared.fetchToc(
            bookUrl: bookPage, source: source, maxPages: 10,
            fetchPage: { try await fixture.fetch($0, referer: $1) }
        )
        XCTAssertEqual(result.chapters.count, 5)
        XCTAssertFalse(result.complete, "a preview-only fallback must never be labelled complete")
    }
}
