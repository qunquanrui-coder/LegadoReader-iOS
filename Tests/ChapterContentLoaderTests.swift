import XCTest
@testable import LegadoReader

private actor FixturePages {
    let pages: [String: String]
    var requested: [String] = []
    init(_ pages: [String: String]) { self.pages = pages }
    func fetch(_ url: String, referer: String?) throws -> (String, URL) {
        requested.append(url)
        guard let html = pages[url], let parsedURL = URL(string: url) else { throw URLError(.timedOut) }
        return (html, parsedURL)
    }
}

final class ChapterContentLoaderTests: XCTestCase {
    private let first = "https://fixture.invalid/book/100.html"
    private let second = "https://fixture.invalid/book/100_2.html"
    private let third = "https://fixture.invalid/book/100_3.html"
    private let nextChapter = "https://fixture.invalid/book/101.html"

    private func source(explicitRule: Bool = true) -> BookSource {
        BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://fixture.invalid",
                   ruleContent: RuleContent(content: "#content@html", nextContentUrl: explicitRule ? "a.next@href" : nil))
    }
    private func chapter() -> Chapter { Chapter(index: 0, title: "第一章 测试", url: first) }
    private func page(_ body: String, next: String? = nil, label: String = "下一页", title: String = "第一章 测试") -> String {
        "<h1>\(title)</h1><div id='content'><p>\(body)</p></div>"
            + (next.map { "<a class='next' href='\($0)'>\(label)</a>" } ?? "")
    }
    private func loader(_ pages: FixturePages, maxPages: Int = 100) -> ChapterContentLoader {
        ChapterContentLoader(maxPages: maxPages) { try await pages.fetch($0, referer: $1) }
    }

    func testThreePagesIncludeFinalParagraphAndNeverFetchNextChapter() async throws {
        let pages = FixturePages([
            first: page("第一页开头。", next: second),
            second: page("第二页中间。", next: third, title: "第一章 测试（2/3）"),
            third: page("最后一页的章尾关键剧情。", next: nextChapter, label: "下一章"),
            nextChapter: page("不能拼入第二章。", title: "第二章 新章"),
        ])
        let result = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil, nextChapterURL: nextChapter)
        XCTAssertEqual(result.pageCount, 3)
        XCTAssertTrue(result.text.contains("最后一页的章尾关键剧情。"))
        XCTAssertFalse(result.text.contains("不能拼入第二章"))
        let requested = await pages.requested
        XCTAssertEqual(requested, [first, second, third])
    }

    func testGenericNextPageWorksWithoutSourcePaginationRule() async throws {
        let pages = FixturePages([first: page("开头。", next: second), second: page("完整章尾。")])
        let result = try await loader(pages).load(chapter: chapter(), source: source(explicitRule: false), referer: nil)
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertTrue(result.text.hasSuffix("完整章尾。"))
    }

    func testNextChapterLinkIsNotTreatedAsAnotherPage() async throws {
        let pages = FixturePages([first: page("已完成。", next: nextChapter, label: "下一章")])
        let result = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil, nextChapterURL: nextChapter)
        XCTAssertEqual(result.pageCount, 1)
        let requested = await pages.requested
        XCTAssertEqual(requested, [first])
    }

    func testLaterPageFailureDoesNotReturnOrCachePartialChapter() async throws {
        let pages = FixturePages([first: page(String(repeating: "第一页正文。", count: 30), next: second)])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ChapterContentCache(directory: directory)
        do {
            let result = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
            cache.save(result, bookId: "test", chapterIndex: 0)
            XCTFail("A partial first page must not be returned as a complete chapter")
        } catch ChapterLoadingError.incompletePage(let page) {
            XCTAssertEqual(page, 2)
        }
        XCTAssertNil(cache.read(bookId: "test", chapterIndex: 0))
    }

    func testUnfinishedNoticeWithoutUsableLinkFailsClearly() async throws {
        let pages = FixturePages([first: page("剧情尚未结束。本章未完，点击下一页继续阅读。")])
        do {
            _ = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
            XCTFail("An unfinished chapter must not silently succeed")
        } catch ChapterLoadingError.ambiguousNextPage { }
    }

    func testPaginationCycleIsRejected() async throws {
        let pages = FixturePages([first: page("第一页。", next: second), second: page("第二页。", next: first)])
        do {
            _ = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
            XCTFail("Cycle must fail")
        } catch ChapterLoadingError.paginationLoop { }
    }

    func testPageLimitCannotProduceCompleteContent() async throws {
        let pages = FixturePages([first: page("第一页。", next: second)])
        do {
            _ = try await loader(pages, maxPages: 1).load(chapter: chapter(), source: source(), referer: nil)
            XCTFail("Limit must fail rather than truncate")
        } catch ChapterLoadingError.pageLimit { }
    }

    func testMislabelledLinkCannotAppendDifferentChapter() async throws {
        let pages = FixturePages([first: page("第一页。", next: nextChapter),
                                  nextChapter: page("这是第二章的正文。", title: "第二章 新章")])
        do {
            _ = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
            XCTFail("A different chapter must not be appended")
        } catch ChapterLoadingError.differentChapter { }
    }

    func testValidShortChapterIsNotReplacedWithErrorText() async throws {
        let pages = FixturePages([first: page("完。")])
        let result = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
        XCTAssertTrue(result.text.hasSuffix("完。"))
        XCTAssertEqual(result.pageCount, 1)
    }

    func testMissingContentThrowsInsteadOfReturningCacheableErrorMessage() async throws {
        let pages = FixturePages([first: "<html><body>服务暂时不可用</body></html>"])
        do {
            _ = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
            XCTFail("Error text must not become chapter content")
        } catch ChapterLoadingError.missingContent { }
    }

    func testCancelledLoadCannotReturnCompleteChapter() async throws {
        let delayed = ChapterContentLoader { _, _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return ("<div id='content'>章尾</div>", URL(string: "https://fixture.invalid/book/100.html")!)
        }
        let task = Task { try await delayed.load(chapter: chapter(), source: source(), referer: nil) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled requests must not return content") }
        catch is CancellationError { }
    }

    func testPageCounterWithoutContinuationLinkIsIncomplete() async throws {
        let pages = FixturePages([first: page("第一页正文。", title: "第一章 测试（1/2）")])
        do {
            _ = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
            XCTFail("A page counter must not be mistaken for a complete chapter")
        } catch ChapterLoadingError.ambiguousNextPage { }
    }

    func testEquivalentArabicAndChineseChapterNumbersAreAccepted() async throws {
        let pages = FixturePages([first: page("第一部分。", next: second),
                                  second: page("最后一部分。", title: "第1章 测试（2/2）")])
        let result = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
        XCTAssertEqual(result.pageCount, 2)
        XCTAssertTrue(result.text.hasSuffix("最后一部分。"))
    }

    func testDisabledNextPageAtChapterEndDoesNotLoop() async throws {
        let html = page("完整章尾。") + "<a class='next' href='#' aria-disabled='true'>下一页</a>"
        let pages = FixturePages([first: html])
        let result = try await loader(pages).load(chapter: chapter(), source: source(), referer: nil)
        XCTAssertEqual(result.pageCount, 1)
    }
}
