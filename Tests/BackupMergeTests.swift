import XCTest
@testable import LegadoReader

final class BackupMergeTests: XCTestCase {
    private func book(title: String = "测试书", author: String = "测试作者",
                      chapter: Int, paragraph: Int = 0,
                      readAt: Date, totalChapters: Int = 300) -> Book {
        Book(title: title, author: author,
             sourceUrl: "https://source.invalid", sourceName: "测试源",
             bookUrl: "https://source.invalid/book/1",
             currentChapterIndex: chapter,
             currentChapterTitle: "第\(chapter)章 标题",
             currentParagraphIndex: paragraph,
             lastReadTime: readAt,
             totalChapters: totalChapters)
    }

    private func key(_ book: Book) -> String {
        StorageManager.bookKey(title: book.title, author: book.author)
    }

    func testOlderBackupDoesNotRollBackNewerLocalPosition() {
        let now = Date()
        let local = book(chapter: 200, paragraph: 8, readAt: now)
        let backup = book(chapter: 100, paragraph: 3, readAt: now.addingTimeInterval(-3600))
        let localKey = key(local)

        let result = StorageManager.mergeBackupState(
            localBooks: [local],
            localPositions: [localKey: [200, 8]],
            localTitles: [localKey: "第200章 标题"],
            backupBooks: [backup],
            backupPositions: [localKey: [100, 3]],
            backupTitles: [localKey: "第100章 标题"]
        )

        XCTAssertEqual(result.bookshelf.count, 1)
        XCTAssertEqual(result.bookshelf[0].currentChapterIndex, 200)
        XCTAssertEqual(result.bookshelf[0].currentParagraphIndex, 8)
        XCTAssertEqual(result.positions[localKey], [200, 8])
        XCTAssertEqual(result.titles[localKey], "第200章 标题")
    }

    func testNewerBackupWinsShelfAndBothMaps() {
        let now = Date()
        let local = book(chapter: 100, paragraph: 0, readAt: now.addingTimeInterval(-7200))
        let backup = book(chapter: 150, paragraph: 4, readAt: now)
        let localKey = key(local)

        let result = StorageManager.mergeBackupState(
            localBooks: [local],
            localPositions: [localKey: [100, 0]],
            localTitles: [localKey: "第100章 标题"],
            backupBooks: [backup],
            backupPositions: [localKey: [150, 4]],
            backupTitles: [localKey: "第150章 标题"]
        )

        XCTAssertEqual(result.bookshelf[0].currentChapterIndex, 150)
        XCTAssertEqual(result.positions[localKey], [150, 4])
        XCTAssertEqual(result.titles[localKey], "第150章 标题")
    }

    func testEqualTimestampsUseHigherChapterIndex() {
        let stamp = Date()
        let local = book(chapter: 100, readAt: stamp)
        let backup = book(chapter: 120, readAt: stamp)
        let localKey = key(local)

        let result = StorageManager.mergeBackupState(
            localBooks: [local],
            localPositions: [localKey: [100, 0]],
            localTitles: [:],
            backupBooks: [backup],
            backupPositions: [localKey: [120, 2]],
            backupTitles: [:]
        )

        XCTAssertEqual(result.bookshelf[0].currentChapterIndex, 120)
        XCTAssertEqual(result.positions[localKey], [120, 2])
    }

    func testBackupOnlyBookIsAddedAndMapsRebuilt() {
        let existing = book(title: "已有书", chapter: 10, readAt: Date())
        let incoming = book(title: "新书", chapter: 33, paragraph: 7, readAt: Date())
        let incomingKey = key(incoming)

        let result = StorageManager.mergeBackupState(
            localBooks: [existing],
            localPositions: [key(existing): [10, 0]],
            localTitles: [key(existing): "第10章 标题"],
            backupBooks: [incoming],
            backupPositions: [incomingKey: [33, 7]],
            backupTitles: [incomingKey: "第33章 标题"]
        )

        XCTAssertEqual(result.bookshelf.count, 2)
        XCTAssertEqual(result.positions[incomingKey], [33, 7])
        XCTAssertEqual(result.titles[incomingKey], "第33章 标题")
    }

    func testOrphanBackupPositionIsPreservedOnlyWhenMissingLocally() {
        let local = book(chapter: 5, readAt: Date())
        let localKey = key(local)
        let orphanKey = "孤儿书_作者"

        let result = StorageManager.mergeBackupState(
            localBooks: [local],
            localPositions: [localKey: [5, 0], orphanKey: [9, 9]],
            localTitles: [:],
            backupBooks: [local],
            backupPositions: [localKey: [1, 0], orphanKey: [2, 2]],
            backupTitles: [:]
        )

        XCTAssertEqual(result.positions[orphanKey], [9, 9])
        XCTAssertEqual(result.positions[localKey], [5, 0])
    }

    func testDriftedLocalMapsAreRewrittenFromShelf() {
        let local = book(chapter: 200, paragraph: 6, readAt: Date())
        let localKey = key(local)

        let result = StorageManager.mergeBackupState(
            localBooks: [local],
            localPositions: [localKey: [100, 1]],
            localTitles: [localKey: "第100章 标题"],
            backupBooks: [],
            backupPositions: [:],
            backupTitles: [:]
        )

        XCTAssertEqual(result.positions[localKey], [200, 6])
        XCTAssertEqual(result.titles[localKey], "第200章 标题")
    }

    func testNewerRuleComparesTimestampThenChapter() {
        let older = book(chapter: 300, readAt: Date(timeIntervalSince1970: 100))
        let newer = book(chapter: 100, readAt: Date(timeIntervalSince1970: 200))
        XCTAssertTrue(StorageManager.isNewerReadingState(newer, than: older))
        XCTAssertFalse(StorageManager.isNewerReadingState(older, than: newer))

        let sameStamp = Date(timeIntervalSince1970: 200)
        let low = book(chapter: 10, readAt: sameStamp)
        let high = book(chapter: 11, readAt: sameStamp)
        XCTAssertTrue(StorageManager.isNewerReadingState(high, than: low))
        XCTAssertFalse(StorageManager.isNewerReadingState(low, than: high))
    }
}

final class TocChapterResolutionTests: XCTestCase {
    private let chapters = [
        Chapter(index: 0, title: "第一章 开始", url: "https://fixture.invalid/c/1.html"),
        Chapter(index: 1, title: "第二章 继续", url: "https://fixture.invalid/c/2.html"),
        Chapter(index: 2, title: "第三章 结束", url: "https://fixture.invalid/c/3.html")
    ]

    func testExactURLWinsOverIndex() {
        let resolved = ChapterTextFormatter.resolvedChapterIndex(
            in: chapters, preferredURL: "https://fixture.invalid/c/3.html",
            preferredTitle: "第一章 开始", fallbackIndex: 0
        )
        XCTAssertEqual(resolved, 2)
    }

    func testTitleFallbackWhenURLChanged() {
        let resolved = ChapterTextFormatter.resolvedChapterIndex(
            in: chapters, preferredURL: "https://fixture.invalid/old/2.html",
            preferredTitle: "第二章 继续", fallbackIndex: 0
        )
        XCTAssertEqual(resolved, 1)
    }

    func testClampsFallbackIndexWhenNothingMatches() {
        XCTAssertEqual(ChapterTextFormatter.resolvedChapterIndex(
            in: chapters, preferredURL: nil, preferredTitle: nil, fallbackIndex: 99), 2)
        XCTAssertEqual(ChapterTextFormatter.resolvedChapterIndex(
            in: chapters, preferredURL: nil, preferredTitle: nil, fallbackIndex: -5), 0)
        XCTAssertEqual(ChapterTextFormatter.resolvedChapterIndex(
            in: [], preferredURL: nil, preferredTitle: nil, fallbackIndex: 3), 0)
    }
}
