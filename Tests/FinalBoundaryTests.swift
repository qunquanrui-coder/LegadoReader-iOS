import XCTest
@testable import LegadoReader

final class CacheIdentityTests: XCTestCase {
    private func book(sourceUrl: String, sourceName: String, bookUrl: String,
                      title: String = "边界之书", author: String = "作者") -> Book {
        Book(title: title, author: author, sourceUrl: sourceUrl, sourceName: sourceName, bookUrl: bookUrl)
    }

    func testReplacingSourceKeepsPersistedShelfIdentity() {
        let shelfBook = book(sourceUrl: "https://a.invalid", sourceName: "A",
                             bookUrl: "https://a.invalid/book/1")
        var incoming = book(sourceUrl: "https://b.invalid", sourceName: "B",
                            bookUrl: "https://b.invalid/book/1")
        incoming.latestChapter = "第9章 新的"
        incoming.coverUrl = "https://b.invalid/cover.jpg"

        let updated = StorageManager.bookByReplacingSource(of: shelfBook, with: incoming)

        XCTAssertEqual(updated.id, shelfBook.id,
                       "cache/progress identity must stay canonical after a source switch")
        XCTAssertEqual(updated.sourceUrl, "https://b.invalid")
        XCTAssertEqual(updated.sourceName, "B")
        XCTAssertEqual(updated.bookUrl, "https://b.invalid/book/1")
        XCTAssertEqual(updated.latestChapter, "第9章 新的")
        XCTAssertEqual(updated.coverUrl, "https://b.invalid/cover.jpg")
        XCTAssertEqual(updated.currentChapterIndex, shelfBook.currentChapterIndex)
    }

    func testSourceVariantsSharePersistedIDButNeedDistinctRowIdentity() {
        let original = book(sourceUrl: "https://a.invalid", sourceName: "A",
                            bookUrl: "https://same.invalid/book/1")
        let alternative = book(sourceUrl: "https://a.invalid#alternate-rules", sourceName: "A #2",
                               bookUrl: "https://same.invalid/book/1")

        // Same work + same book URL: persisted cache identity is intentionally identical …
        XCTAssertEqual(original.id, alternative.id)
        // … so the search UI must use the source-aware row identity instead.
        XCTAssertNotEqual(original.searchResultID, alternative.searchResultID)

        let differentBook = book(sourceUrl: "https://a.invalid", sourceName: "A",
                                 bookUrl: "https://other.invalid/book/1")
        XCTAssertNotEqual(original.id, differentBook.id)
    }

    func testAddingSameWorkFromAnotherSourceReturnsShelfIdentity() {
        let storage = StorageManager.shared
        let originalShelf = storage.bookshelf
        let originalLastRead = storage.lastReadBookId
        defer {
            storage.bookshelf = originalShelf
            storage.lastReadBookId = originalLastRead
            storage.saveBookshelf()
        }

        let shelfBook = book(sourceUrl: "https://a.invalid", sourceName: "A",
                             bookUrl: "https://a.invalid/book/1")
        storage.bookshelf = [shelfBook]

        let searchResult = book(sourceUrl: "https://b.invalid", sourceName: "B",
                                bookUrl: "https://b.invalid/book/1")
        let canonical = storage.addBookToShelf(searchResult)

        XCTAssertEqual(canonical.id, shelfBook.id,
                       "downloads from another source must use the shelf's cache directory")
        XCTAssertEqual(storage.bookshelf.count, 1)
        XCTAssertEqual(storage.bookshelf.first?.id, shelfBook.id)
        XCTAssertEqual(storage.bookshelf.first?.sourceUrl, "https://b.invalid")
        XCTAssertEqual(storage.bookshelf.first?.bookUrl, "https://b.invalid/book/1")
    }

    func testRemovingBookFromShelfClearsSavedPositionAndTitleRecords() {
        let storage = StorageManager.shared
        let originalShelf = storage.bookshelf
        let originalLastRead = storage.lastReadBookId
        defer {
            storage.bookshelf = originalShelf
            storage.lastReadBookId = originalLastRead
            storage.saveBookshelf()
        }

        let testBook = book(sourceUrl: "https://a.invalid", sourceName: "A",
                            bookUrl: "https://a.invalid/book/cleanup",
                            title: "删书清理测试_\(UUID().uuidString)", author: "测试作者")
        _ = storage.addBookToShelf(testBook)
        storage.updateBookProgress(bookId: testBook.id, bookTitle: testBook.title, bookAuthor: testBook.author,
                                   chapterIndex: 88, chapterTitle: "第88章 旧进度", totalChapters: 100,
                                   paragraphIndex: 6, characterOffset: 42)
        XCTAssertEqual(storage.getSavedReadingPosition(for: testBook).chapterIndex, 88)
        XCTAssertEqual(storage.savedChapterTitle(for: testBook), "第88章 旧进度")

        storage.removeBookFromShelf(testBook)

        let freshCopy = book(sourceUrl: "https://b.invalid", sourceName: "B",
                             bookUrl: "https://b.invalid/book/cleanup",
                             title: testBook.title, author: testBook.author)
        let posAfterRemove = storage.getSavedReadingPosition(for: freshCopy)
        XCTAssertEqual(posAfterRemove.chapterIndex, 0)
        XCTAssertEqual(posAfterRemove.paragraphIndex, 0)
        XCTAssertEqual(posAfterRemove.characterOffset, 0)
        XCTAssertNil(storage.savedChapterTitle(for: freshCopy))
        XCTAssertNil(storage.consumePendingRelocation(for: freshCopy))
    }
}

final class LoadTokenSetTests: XCTestCase {
    func testNewRequestSupersedesItsOlderCompletion() {
        var tokens = LoadTokenSet()
        let first = tokens.beginChapterLoad()
        XCTAssertTrue(tokens.isCurrentChapterLoad(first))

        let second = tokens.beginChapterLoad()
        XCTAssertFalse(tokens.isCurrentChapterLoad(first), "an older completion must be ignored")
        XCTAssertTrue(tokens.isCurrentChapterLoad(second))
    }

    func testDismissingReaderInvalidatesInFlightChapterAndTocLoads() {
        var tokens = LoadTokenSet()
        let chapterLoad = tokens.beginChapterLoad()
        let tocLoad = tokens.beginTocLoad()

        tokens.invalidateAll()

        XCTAssertFalse(tokens.isCurrentChapterLoad(chapterLoad),
                       "a dismissed reader must reject late chapter responses (no progress overwrite)")
        XCTAssertFalse(tokens.isCurrentTocLoad(tocLoad),
                       "a dismissed reader must reject late catalogue responses")
    }

    func testChapterAndTocIdentitiesAreIndependent() {
        var tokens = LoadTokenSet()
        let chapterLoad = tokens.beginChapterLoad()
        let tocLoad = tokens.beginTocLoad()

        XCTAssertTrue(tokens.isCurrentChapterLoad(chapterLoad))
        XCTAssertTrue(tokens.isCurrentTocLoad(tocLoad))
        XCTAssertFalse(tokens.isCurrentChapterLoad(tocLoad))
        XCTAssertFalse(tokens.isCurrentTocLoad(chapterLoad))
    }
}
