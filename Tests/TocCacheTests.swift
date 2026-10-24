import XCTest
@testable import LegadoReader

final class TocCacheTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func chapters() -> [Chapter] {
        [Chapter(index: 0, title: "第一章 开始", url: "https://fixture.invalid/c/1.html"),
         Chapter(index: 1, title: "第二章 继续", url: "https://fixture.invalid/c/2.html")]
    }

    func testRoundTripPreservesChaptersAndCompleteness() throws {
        let cache = TocCache(directory: try temporaryDirectory())
        XCTAssertTrue(cache.save(bookId: "book", sourceURL: "https://fixture.invalid",
                                 bookURL: "https://fixture.invalid/book/1", chapters: chapters(), complete: false))
        let snapshot = cache.read(bookId: "book", sourceURL: "https://fixture.invalid",
                                  bookURL: "https://fixture.invalid/book/1")
        XCTAssertEqual(snapshot?.chapters, chapters())
        XCTAssertEqual(snapshot?.complete, false)
        XCTAssertNotNil(snapshot?.fetchedAt)
    }

    func testSourceOrBookURLMismatchInvalidatesSnapshot() throws {
        let cache = TocCache(directory: try temporaryDirectory())
        XCTAssertTrue(cache.save(bookId: "book", sourceURL: "https://fixture.invalid",
                                 bookURL: "https://fixture.invalid/book/1", chapters: chapters(), complete: true))
        XCTAssertNil(cache.read(bookId: "book", sourceURL: "https://other.invalid",
                                bookURL: "https://fixture.invalid/book/1"))
        XCTAssertNil(cache.read(bookId: "book", sourceURL: "https://fixture.invalid",
                                bookURL: "https://fixture.invalid/book/2"))
        XCTAssertNil(cache.read(bookId: "another-book", sourceURL: "https://fixture.invalid",
                                bookURL: "https://fixture.invalid/book/1"))
    }

    func testEmptyAndCorruptRecordsAreRejected() throws {
        let directory = try temporaryDirectory()
        let cache = TocCache(directory: directory)
        XCTAssertFalse(cache.save(bookId: "book", sourceURL: "https://fixture.invalid",
                                  bookURL: "https://fixture.invalid/book/1", chapters: [], complete: true))
        XCTAssertNil(cache.read(bookId: "book", sourceURL: "https://fixture.invalid",
                                bookURL: "https://fixture.invalid/book/1"))

        let bookDirectory = directory.appendingPathComponent("book")
        try FileManager.default.createDirectory(at: bookDirectory, withIntermediateDirectories: true)
        try "not json".write(to: bookDirectory.appendingPathComponent("toc.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(cache.read(bookId: "book", sourceURL: "https://fixture.invalid",
                                bookURL: "https://fixture.invalid/book/1"))
    }

    func testRemoveDeletesSnapshot() throws {
        let cache = TocCache(directory: try temporaryDirectory())
        XCTAssertTrue(cache.save(bookId: "book", sourceURL: "https://fixture.invalid",
                                 bookURL: "https://fixture.invalid/book/1", chapters: chapters(), complete: true))
        cache.remove(bookId: "book")
        XCTAssertNil(cache.read(bookId: "book", sourceURL: "https://fixture.invalid",
                                bookURL: "https://fixture.invalid/book/1"))
    }
}
