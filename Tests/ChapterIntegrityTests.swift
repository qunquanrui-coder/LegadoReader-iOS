import XCTest
@testable import LegadoReader

final class ChapterIntegrityTests: XCTestCase {
    private let baseURL = URL(string: "https://fixture.invalid/book/1.html")!

    private func source() -> BookSource {
        BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://fixture.invalid",
                   ruleContent: RuleContent(content: "#content@html"))
    }

    func testNovelTextWithCommaBraceKeepsChapterTail() throws {
        let html = "<div id='content'><p>\(String(repeating: "章节开头正文。", count: 20))</p>"
            + "<p>屏幕返回,{\"message\":\"线索\"}</p><p>章尾关键剧情必须保留。</p></div>"
        let text = try LegadoParser.shared.parseContent(html: html, baseUrl: baseURL, source: source())
        XCTAssertTrue(text.contains("章尾关键剧情必须保留。"))
        XCTAssertTrue(text.contains(",{\"message\""))
    }

    func testNarrativeSentenceContainingReadingWordIsPreserved() throws {
        let html = "<div id='content'><p>\(String(repeating: "章节开头正文。", count: 20))</p>"
            + "<p>他打开手机阅读那封信，终于知道失踪者的下落。</p></div>"
        let text = try LegadoParser.shared.parseContent(html: html, baseUrl: baseURL, source: source())
        XCTAssertTrue(text.contains("他打开手机阅读那封信，终于知道失踪者的下落。"))
    }
}
