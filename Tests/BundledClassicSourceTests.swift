import Foundation
import XCTest
@testable import LegadoReader

final class BundledClassicSourceTests: XCTestCase {
    func testWikisourceKeepsFinalParagraphAndExcludesSubpagesFromSearch() throws {
        let source = try bundledSource("https://zh.wikisource.org")
        let url = try XCTUnwrap(URL(string: source.bookSourceUrl))
        let books = try LegadoParser.shared.parseSearch(html: """
            <ul><li class="mw-search-result-ns-0">
              <div class="mw-search-result-heading"><a title="古典小说/第一回" href="/wiki/chapter1">第一回</a></div>
            </li><li class="mw-search-result-ns-0">
              <div class="mw-search-result-heading"><a title="古典小说" href="/wiki/book">古典小说</a></div>
            </li></ul>
            """, baseUrl: url, source: source)
        XCTAssertEqual(books.map(\.title), ["古典小说"])
        let text = try LegadoParser.shared.parseContent(html: """
            <div class="mw-parser-output"><div class="prose">
              <p>这是章节第一段。</p><p>这是章节最后一段。</p>
            </div></div>
            """, baseUrl: url, source: source)
        let paragraphs = text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(paragraphs, ["这是章节第一段。", "这是章节最后一段。"])
    }

    func testWuguoUsesTheVisibleCatalogueOrder() throws {
        let source = try bundledSource("https://wuguo.org")
        let url = try XCTUnwrap(URL(string: source.bookSourceUrl))
        let rows = (1...3).map { "<a class=\"novel-catalog-text-row\" href=\"/chapter/\($0)\"><span class=\"truncate\">第\($0)回</span></a>" }
        let html = """
            <div class="novel-catalog-text-rows" x-cloak>\(rows.reversed().joined())</div>
            <div class="novel-catalog-text-rows">\(rows.joined())</div>
            """
        let chapters = try LegadoParser.shared.parseToc(html: html, baseUrl: url, source: source)
        XCTAssertEqual(chapters.map(\.title), ["第1回", "第2回", "第3回"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
    }

    private func bundledSource(_ identity: String) throws -> BookSource {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "default_sources", withExtension: "json"))
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: url))
        return try XCTUnwrap(sources.first { $0.bookSourceUrl == identity })
    }
}
