import XCTest
@testable import LegadoReader

final class ChapterContentCacheTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func content() -> CompleteChapterContent {
        CompleteChapterContent(text: "第一页\n\n最后一页章尾", chapterURL: "https://fixture.invalid/100.html",
                               sourceURL: "https://fixture.invalid", pageCount: 3)
    }

    func testCompleteChapterRoundTripPreservesTailAndProvenance() throws {
        let cache = ChapterContentCache(directory: try temporaryDirectory())
        XCTAssertTrue(cache.save(content(), bookId: "book", chapterIndex: 0))
        XCTAssertEqual(cache.read(bookId: "book", chapterIndex: 0, chapterURL: content().chapterURL,
                                  sourceURL: content().sourceURL), content().text)
        XCTAssertNil(cache.read(bookId: "book", chapterIndex: 0, chapterURL: "https://fixture.invalid/101.html"))
        XCTAssertNil(cache.read(bookId: "book", chapterIndex: 0, sourceURL: "https://other.invalid"))
    }

    func testLegacyPlainTextIsNotAcceptedAsCompleteCache() throws {
        let directory = try temporaryDirectory()
        let book = directory.appendingPathComponent("book")
        try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)
        try "只有前半章".write(to: book.appendingPathComponent("0.txt"), atomically: true, encoding: .utf8)
        let cache = ChapterContentCache(directory: directory)
        XCTAssertNil(cache.read(bookId: "book", chapterIndex: 0))
        XCTAssertTrue(cache.save(content(), bookId: "book", chapterIndex: 0))
        XCTAssertEqual(cache.read(bookId: "book", chapterIndex: 0), content().text)
    }

    func testIncompleteAndUnknownVersionRecordsAreRejected() throws {
        let directory = try temporaryDirectory()
        let book = directory.appendingPathComponent("book")
        try FileManager.default.createDirectory(at: book, withIntermediateDirectories: true)
        for (version, complete) in [(1, false), (0, true)] {
            let record: [String: Any] = ["version": version, "complete": complete, "chapterURL": content().chapterURL,
                                         "sourceURL": content().sourceURL, "pageCount": 1, "text": "半章"]
            try JSONSerialization.data(withJSONObject: record).write(to: book.appendingPathComponent("0.json"))
            XCTAssertNil(ChapterContentCache(directory: directory).read(bookId: "book", chapterIndex: 0))
        }
    }
}
