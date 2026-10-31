import XCTest
@testable import LegadoReader

final class FinalDataFlowTests: XCTestCase {
    private func isolated(onRemoval: ((Book) -> Void)? = { _ in }) throws -> (StorageManager, UserDefaults) {
        let suite = "FinalDataFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let storage = StorageManager(defaults: defaults, cacheDirectoryURL: root.appendingPathComponent("cache"),
                                     loadDefaults: false, onBookRemoval: onRemoval)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return (storage, defaults)
    }

    private func book(source: String = "a", chapter: Int = 0, title: String? = nil, readAt: TimeInterval = 100) -> Book {
        Book(title: "边界封测", author: "测试作者", sourceUrl: "https://\(source).invalid", sourceName: source,
             bookUrl: "https://\(source).invalid/book/1", currentChapterIndex: chapter,
             currentChapterTitle: title, lastReadTime: Date(timeIntervalSince1970: readAt), totalChapters: 100)
    }

    private func content(source: String = "a", chapter: Int = 0) -> CompleteChapterContent {
        CompleteChapterContent(text: "完整章节的开头和结尾。", chapterURL: "https://\(source).invalid/c/\(chapter)",
                               sourceURL: "https://\(source).invalid", pageCount: 1)
    }

    private func backup(_ records: [Book], config: ReaderConfig = .default, modifiedAt: Date? = nil) throws -> String {
        let payload = StorageManager.FullBackupPayload(bookshelf: records, bookSources: [], readerConfig: config,
            lastReadBookId: records.first?.id, positionMap: [:], chapterTitleMap: [:], readerConfigUpdatedAt: modifiedAt)
        return try XCTUnwrap(String(data: JSONEncoder().encode(payload), encoding: .utf8))
    }

    func testDeleteRejectsLateProgressCacheAndTocEvenAfterExplicitReAdd() throws {
        let (storage, _) = try isolated()
        let record = storage.addBookToShelf(book())
        let old = storage.bookWriteToken(for: record)
        let chapters = [Chapter(index: 0, title: "第一章", url: content().chapterURL)]
        XCTAssertTrue(storage.saveCachedToc(for: record, chapters: chapters, complete: true, writeToken: old))
        XCTAssertTrue(storage.saveChapterCache(bookId: record.id, chapterIndex: 0, content: content(), writeToken: old))
        storage.updateBookProgress(bookId: record.id, bookTitle: record.title, bookAuthor: record.author,
            chapterIndex: 7, chapterTitle: "第八章", totalChapters: 100, paragraphIndex: 2, writeToken: old)
        storage.removeBookFromShelf(record)
        XCTAssertFalse(storage.acceptsBookWrite(old))
        XCTAssertFalse(storage.saveChapterCache(bookId: record.id, chapterIndex: 0, content: content(), writeToken: old))
        XCTAssertFalse(storage.saveChapterCache(bookId: record.id, chapterIndex: 0, content: content()))
        XCTAssertFalse(storage.saveCachedToc(for: record, chapters: chapters, complete: true, writeToken: old))
        storage.updateBookProgress(bookId: record.id, bookTitle: record.title, bookAuthor: record.author,
            chapterIndex: 99, chapterTitle: "旧回调", totalChapters: 100)
        XCTAssertEqual(storage.getSavedReadingPosition(for: record).chapterIndex, 0)
        XCTAssertNil(storage.loadCachedToc(for: record))
        XCTAssertNil(storage.getCachedChapter(bookId: record.id, chapterIndex: 0,
            chapterURL: content().chapterURL, sourceURL: record.sourceUrl))

        _ = storage.addBookToShelf(record)
        XCTAssertFalse(storage.acceptsBookWrite(old), "Re-adding the same ID must not revive pre-delete work")
        storage.updateBookProgress(bookId: record.id, bookTitle: record.title, bookAuthor: record.author,
            chapterIndex: 99, chapterTitle: "旧回调", totalChapters: 100, writeToken: old)
        XCTAssertEqual(storage.getSavedReadingPosition(for: record).chapterIndex, 0)
        let current = storage.bookWriteToken(for: record)
        XCTAssertTrue(storage.acceptsBookWrite(current))
        storage.updateBookProgress(bookId: record.id, chapterIndex: 2, chapterTitle: "第三章", totalChapters: 100,
            paragraphIndex: 3, characterOffset: 48, writeToken: current)
        XCTAssertEqual(storage.getSavedReadingPosition(for: record).characterOffset, 48)
        XCTAssertTrue(storage.saveChapterCache(bookId: record.id, chapterIndex: 0, content: content(), writeToken: current))
    }

    func testRemovalInvalidatesWritesBeforeStoppingThePlaybackOwner() throws {
        var storageRef: StorageManager?
        var token: BookWriteToken?
        var removalCount = 0
        let (storage, _) = try isolated(onRemoval: { _ in
            removalCount += 1
            if let token { XCTAssertFalse(storageRef?.acceptsBookWrite(token) ?? true) }
        })
        storageRef = storage
        let record = storage.addBookToShelf(book())
        token = storage.bookWriteToken(for: record)
        storage.removeBookFromShelf(record)
        XCTAssertEqual(removalCount, 1)
    }

    func testSourceReplacementInvalidatesTheOriginalWorkToken() throws {
        let (storage, _) = try isolated()
        let original = storage.addBookToShelf(book())
        let old = storage.bookWriteToken(for: original)
        let replaced = storage.replaceBookSource(for: original, with: book(source: "b"))
        XCTAssertEqual(replaced.id, original.id)
        XCTAssertFalse(storage.acceptsBookWrite(old))
        XCTAssertFalse(storage.saveChapterCache(bookId: original.id, chapterIndex: 0, content: content(), writeToken: old))
        let current = storage.bookWriteToken(for: replaced)
        XCTAssertTrue(storage.acceptsBookWrite(current))
        XCTAssertTrue(storage.saveChapterCache(bookId: replaced.id, chapterIndex: 0,
            content: content(source: "b"), writeToken: current))
    }

    func testCrossSourceBackupKeepsOfflineSourceAndRelocatesByLocalChapterTitle() throws {
        let (storage, _) = try isolated()
        let local = storage.addBookToShelf(book(title: "第一章 开始"))
        let toc = [Chapter(index: 0, title: "第一章 开始", url: content().chapterURL),
                   Chapter(index: 1, title: "第二章 继续", url: content(chapter: 1).chapterURL)]
        XCTAssertTrue(storage.saveCachedToc(for: local, chapters: toc, complete: true))
        XCTAssertTrue(storage.saveChapterCache(bookId: local.id, chapterIndex: 1, content: content(chapter: 1)))
        let incoming = book(source: "b", chapter: 55, title: "第二章 继续", readAt: 200)
        _ = try storage.restoreFromBackupJSON(backup([incoming]))
        let restored = try XCTUnwrap(storage.bookshelf.first)
        XCTAssertEqual(restored.id, local.id)
        XCTAssertEqual(restored.sourceUrl, local.sourceUrl)
        XCTAssertEqual(restored.bookUrl, local.bookUrl)
        XCTAssertEqual(restored.currentChapterIndex, 1, "The backup's index 55 is not a local TOC index")
        XCTAssertEqual(storage.getSavedReadingPosition(for: restored).chapterIndex, 1)
        XCTAssertNotNil(storage.loadCachedToc(for: restored))
        XCTAssertNotNil(storage.getCachedChapter(bookId: restored.id, chapterIndex: 1,
            chapterURL: toc[1].url, sourceURL: restored.sourceUrl))
        XCTAssertEqual(storage.cachedChapterIndices(bookId: restored.id, sourceURL: restored.sourceUrl, chapters: toc), [1])
    }

    func testCrossSourceBackupWithoutLocalTocDefersTitleAlignmentInsteadOfCopyingIndex() throws {
        let (storage, _) = try isolated()
        let local = storage.addBookToShelf(book(chapter: 3, title: "第四章 本地"))
        _ = try storage.restoreFromBackupJSON(backup([book(source: "b", chapter: 55, title: "第五十章 对齐目标", readAt: 200)]))
        let restored = try XCTUnwrap(storage.bookshelf.first)
        XCTAssertEqual(restored.id, local.id)
        XCTAssertEqual(restored.sourceUrl, local.sourceUrl)
        XCTAssertEqual(restored.currentChapterIndex, 3)
        XCTAssertEqual(storage.consumePendingRelocation(for: restored), "第五十章 对齐目标")
    }

    func testExplicitBackupSourceChoiceInvalidatesLocalDownloadsAndOldWrites() throws {
        let (storage, _) = try isolated()
        let local = storage.addBookToShelf(book())
        let old = storage.bookWriteToken(for: local)
        XCTAssertTrue(storage.saveChapterCache(bookId: local.id, chapterIndex: 0, content: content()))
        _ = try storage.restoreFromBackupJSON(backup([book(source: "b", chapter: 55, readAt: 200)]), sourcePolicy: .useBackup)
        let restored = try XCTUnwrap(storage.bookshelf.first)
        XCTAssertEqual(restored.id, local.id)
        XCTAssertEqual(restored.sourceUrl, "https://b.invalid")
        XCTAssertFalse(storage.acceptsBookWrite(old))
        XCTAssertNil(storage.getCachedChapter(bookId: local.id, chapterIndex: 0,
            chapterURL: content().chapterURL, sourceURL: local.sourceUrl))
    }

    func testConfigTimestampWinsIndependentlyOfReadingTimestampAndSupportsExplicitChoice() throws {
        let (storage, _) = try isolated()
        _ = storage.addBookToShelf(book(readAt: 100))
        var local = ReaderConfig.default
        local.theme = .pureBlack
        local.effectiveTapMode = .leftHanded
        local.customPurifyRules = []
        storage.readerConfig = local
        storage.saveConfig(updatedAt: Date(timeIntervalSince1970: 300))
        var olderConfig = ReaderConfig.default
        olderConfig.theme = .eyeGreen
        olderConfig.customPurifyRules = ["用户已删除的旧净化规则"]
        let newerRead = book(chapter: 10, readAt: 10000)
        _ = try storage.restoreFromBackupJSON(backup([newerRead], config: olderConfig, modifiedAt: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(storage.readerConfig.theme, .pureBlack)
        XCTAssertEqual(storage.readerConfig.effectiveTapMode, .leftHanded)
        XCTAssertEqual(storage.readerConfig.effectivePurifyRules, [])
        XCTAssertEqual(storage.readerConfigUpdatedAt, Date(timeIntervalSince1970: 300))
        _ = try storage.restoreFromBackupJSON(backup([newerRead], config: olderConfig, modifiedAt: Date(timeIntervalSince1970: 400)))
        XCTAssertEqual(storage.readerConfig.theme, .eyeGreen)
        _ = try storage.restoreFromBackupJSON(backup([], config: local, modifiedAt: Date(timeIntervalSince1970: 100)), configPolicy: .useBackup)
        XCTAssertEqual(storage.readerConfig.theme, .pureBlack)
    }

    func testLegacyBackupPreservesExistingSettingsButRestoresIntoAFreshInstall() throws {
        let (existing, _) = try isolated()
        existing.readerConfig.theme = .pureBlack
        existing.saveConfig(updatedAt: Date(timeIntervalSince1970: 300))
        var old = ReaderConfig.default
        old.theme = .eyeGreen
        let legacy = try backup([], config: old)
        _ = try existing.restoreFromBackupJSON(legacy)
        XCTAssertEqual(existing.readerConfig.theme, .pureBlack)
        let (fresh, _) = try isolated()
        _ = try fresh.restoreFromBackupJSON(legacy)
        XCTAssertEqual(fresh.readerConfig.theme, .eyeGreen)
        let exported = try XCTUnwrap(existing.exportFullBackupJSON())
        let decoded = try JSONDecoder().decode(StorageManager.FullBackupPayload.self, from: Data(exported.utf8))
        XCTAssertEqual(decoded.readerConfigUpdatedAt, Date(timeIntervalSince1970: 300))
    }

    func testReplenishingBuiltInsKeepsCustomRulesAndDisabledOverrides() throws {
        let (storage, _) = try isolated()
        _ = storage.loadDefaultSources()
        var overridden = try XCTUnwrap(storage.bookSources.first)
        overridden.bookSourceName = "我编辑过的内置源"
        overridden.enabled = false
        overridden.searchUrl = "/my-custom-search"
        let custom = BookSource(bookSourceName: "私人规则", bookSourceUrl: "https://custom.invalid")
        storage.bookSources = [overridden, custom]
        _ = storage.loadDefaultSources()
        XCTAssertTrue(storage.bookSources.contains(custom))
        XCTAssertEqual(storage.bookSources.first(where: { $0.bookSourceUrl == overridden.bookSourceUrl }), overridden)
        XCTAssertGreaterThan(storage.bookSources.count, 2)
    }

    func testFullSourceResetCreatesRestorableSnapshotAndRefusesToResetWhenSnapshotFails() throws {
        let (storage, _) = try isolated()
        let custom = BookSource(bookSourceName: "不能丢失的自定义源", bookSourceUrl: "https://custom.invalid", enabled: false)
        storage.bookSources = [custom]
        let url = try storage.resetSourcesToDefaults()
        XCTAssertTrue(storage.hasSourceResetSnapshot)
        XCTAssertEqual(try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: url)), [custom])
        XCTAssertFalse(storage.bookSources.contains(custom))
        let later = BookSource(bookSourceName: "重置后新导入的规则", bookSourceUrl: "https://later.invalid")
        storage.bookSources.append(later)
        _ = try storage.restoreSourcesFromLastResetSnapshot()
        XCTAssertTrue(storage.bookSources.contains(custom))
        XCTAssertTrue(storage.bookSources.contains(later))
        let beforeFailedReset = storage.bookSources
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try storage.resetSourcesToDefaults())
        XCTAssertEqual(storage.bookSources, beforeFailedReset, "A failed recovery snapshot cannot destroy the original rules")
    }
}
