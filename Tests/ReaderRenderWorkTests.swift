import XCTest
import CoreGraphics
@testable import LegadoReader

final class ReaderRenderWorkTests: XCTestCase {
    func testTypographyReusesFormattedTextButTextRulesAndContentInvalidateIt() {
        var cache = ReaderParagraphCache()
        var config = ReaderConfig.default
        let text = "汉语阅读。广告\n第二段。"
        let original = cache.paragraphs(from: text, config: config)
        XCTAssertEqual(cache.formattingCount, 1)
        config.fontSize = 30
        config.lineSpacing = 20
        config.theme = .pureBlack
        config.effectivePageTurnMode = .duoSpread
        config.setTypography(ReaderTypography(fontSize: 25, lineSpacing: 12), for: .wide)
        XCTAssertEqual(cache.paragraphs(from: text, config: config), original)
        XCTAssertEqual(cache.formattingCount, 1)

        config.customPurifyRules = ["广告"]
        let purified = cache.paragraphs(from: text, config: config)
        XCTAssertFalse(purified.joined().contains("广告"))
        XCTAssertEqual(cache.formattingCount, 2)
        config.effectiveChineseConversion = .toTraditional
        let converted = cache.paragraphs(from: text, config: config)
        XCTAssertTrue(converted.joined().contains("漢語閱讀"))
        XCTAssertEqual(cache.formattingCount, 3)
        _ = cache.paragraphs(from: text + "新内容。", config: config)
        XCTAssertEqual(cache.formattingCount, 4)
    }

    @MainActor
    func testBackgroundTextKitMatchesDisplayedPaginationAndPreservesEveryCharacter() async throws {
        let paragraphs = [String(repeating: "正文要完整地跨页保留。👩🏽‍💻e\u{301}", count: 100), "章节最后一段。"]
        let work = makeWork(title: "第一章", paragraphs: paragraphs)
        let expected = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: work.title,
            style: ReaderPageStyle(config: work.config), viewport: work.viewport)
        let worker = ReaderPageWorker()
        let task = Task.detached { try await worker.render(work) }
        let actual = try await task.value
        XCTAssertEqual(actual, expected)
        XCTAssertGreaterThan(actual.count, 2)
        for (index, paragraph) in paragraphs.enumerated() {
            XCTAssertEqual(actual.flatMap(\.items).filter { $0.index == index }.map(\.text).joined(), paragraph)
        }
    }

    func testScrollWorkNeverInvokesThePaginator() async throws {
        let worker = ReaderPageWorker(paginate: { _ in
            XCTFail("Scroll layout must skip TextKit pagination entirely")
            return [ReaderPage(items: [], title: "unexpected")]
        })
        let result = try await worker.render(makeWork(title: "scroll", presentation: .scroll))
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testSameTurnRequestsAreCoalescedBeforeRendering() async throws {
        var rendered: [String] = []
        var committed: [String] = []
        let queue = ReaderReflowQueue(delay: 1, renderer: { work in
            rendered.append(work.title)
            return [ReaderPage(items: [], title: work.title)]
        })
        for title in ["old", "middle", "latest"] {
            queue.request(makeWork(title: title)) { work, _ in committed.append(work.title) }
        }
        let task = try XCTUnwrap(queue.pendingWork)
        await task.value
        XCTAssertEqual(rendered, ["latest"])
        XCTAssertEqual(committed, ["latest"])
    }

    @MainActor
    func testRendererIgnoringCancellationCannotCommitOverNewerLayout() async throws {
        let gate = RenderGate()
        defer { gate.finishAll() }
        let oldStarted = expectation(description: "old renderer started")
        let newStarted = expectation(description: "new renderer started")
        gate.didStart = { title in
            if title == "old" { oldStarted.fulfill() }
            if title == "new" { newStarted.fulfill() }
        }
        let queue = ReaderReflowQueue(delay: 0, renderer: { try await gate.render($0) })
        var committed: [String] = []
        queue.request(makeWork(title: "old")) { work, _ in committed.append(work.title) }
        let oldTask = try XCTUnwrap(queue.pendingWork)
        await fulfillment(of: [oldStarted], timeout: 5)
        queue.request(makeWork(title: "new")) { work, _ in committed.append(work.title) }
        let newTask = try XCTUnwrap(queue.pendingWork)
        await fulfillment(of: [newStarted], timeout: 5)
        gate.finish("new")
        await newTask.value
        gate.finish("old")
        await oldTask.value
        XCTAssertEqual(committed, ["new"])
    }

    @MainActor
    func testDismissalRejectsRendererThatFinishesAfterCancel() async throws {
        let gate = RenderGate()
        defer { gate.finishAll() }
        let started = expectation(description: "renderer started")
        gate.didStart = { _ in started.fulfill() }
        let queue = ReaderReflowQueue(delay: 0, renderer: { try await gate.render($0) })
        var commits = 0
        queue.request(makeWork(title: "dismissed")) { _, _ in commits += 1 }
        let task = try XCTUnwrap(queue.pendingWork)
        await fulfillment(of: [started], timeout: 5)
        queue.cancel()
        gate.finish("dismissed")
        await task.value
        XCTAssertNil(queue.pendingWork)
        XCTAssertEqual(commits, 0)
    }

    @MainActor
    func testCancelBeforeDebounceDoesNotStartRendering() async throws {
        var renderCount = 0
        let queue = ReaderReflowQueue(delay: 1, renderer: { _ in renderCount += 1; return [] })
        queue.request(makeWork(title: "cancelled")) { _, _ in XCTFail("Cancelled work committed") }
        let task = try XCTUnwrap(queue.pendingWork)
        queue.cancel()
        await task.value
        XCTAssertEqual(renderCount, 0)
    }

    private func makeWork(title: String, paragraphs: [String] = ["正文"],
                          presentation: ReaderPresentation = .page) -> ReaderPageWork {
        ReaderPageWork(size: CGSize(width: 700, height: 450), viewport: CGSize(width: 330, height: 420),
                       presentation: presentation, config: .default, paragraphs: paragraphs, title: title)
    }

    @MainActor
    private final class RenderGate {
        var didStart: (String) -> Void = { _ in }
        private var continuations: [String: CheckedContinuation<[ReaderPage], Error>] = [:]
        func render(_ work: ReaderPageWork) async throws -> [ReaderPage] {
            try await withCheckedThrowingContinuation { continuation in
                continuations[work.title] = continuation
                didStart(work.title)
            }
        }
        func finish(_ title: String) {
            continuations.removeValue(forKey: title)?.resume(returning: [ReaderPage(items: [], title: title)])
        }
        func finishAll() {
            let pending = continuations
            continuations.removeAll()
            for (_, continuation) in pending { continuation.resume(returning: []) }
        }
    }
}
