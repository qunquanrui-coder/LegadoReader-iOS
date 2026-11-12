import XCTest
@testable import LegadoReader

final class BundledSourceUpgradeTests: XCTestCase {
    private func isolatedStorage() throws -> (UserDefaults, URL) {
        let suite = "BundledSourceUpgradeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: cache)
        }
        return (defaults, cache)
    }

    func testUpgradeAddsOnlyNewURLsAndKeepsExistingRulesAndOfflineChapter() throws {
        let (defaults, cache) = try isolatedStorage()
        let legacy = BookSource(bookSourceName: "旧内置源", bookSourceUrl: "http://www.shukuge.com")
        let removedLegacy = BookSource(bookSourceName: "已删除的旧内置源", bookSourceUrl: "http://www.qsyz.net")
        let edited = BookSource(bookSourceName: "我的规则", bookSourceUrl: legacy.bookSourceUrl,
                                enabled: false, searchUrl: "/personal-search")
        let custom = BookSource(bookSourceName: "自定义源", bookSourceUrl: "https://custom.invalid", enabled: false)
        let newSource = BookSource(bookSourceName: "新内置源", bookSourceUrl: "https://new.invalid")
        let alreadyImported = BookSource(bookSourceName: "我导入过的新内置源", bookSourceUrl: "https://imported.invalid",
                                          enabled: false, searchUrl: "/my-imported-search")
        let newCatalog = [legacy, removedLegacy, newSource,
                          BookSource(bookSourceName: "新内置规则", bookSourceUrl: alreadyImported.bookSourceUrl)]

        let oldStore = StorageManager(defaults: defaults, cacheDirectoryURL: cache, loadDefaults: false, bundledSources: [])
        oldStore.bookSources = [custom, edited, alreadyImported]
        oldStore.saveBookSources()
        let book = oldStore.addBookToShelf(Book(title: "离线小说", author: "作者", sourceUrl: legacy.bookSourceUrl,
                                               sourceName: edited.bookSourceName, bookUrl: "http://www.shukuge.com/book/1",
                                               currentChapterIndex: 0, lastReadTime: Date(), totalChapters: 1))
        let chapter = CompleteChapterContent(text: "离线正文", chapterURL: "http://www.shukuge.com/book/1/chapter/1",
                                             sourceURL: book.sourceUrl, pageCount: 1)
        XCTAssertTrue(oldStore.saveChapterCache(bookId: book.id, chapterIndex: 0, content: chapter))

        let upgraded = StorageManager(defaults: defaults, cacheDirectoryURL: cache, bundledSources: newCatalog)
        XCTAssertEqual(upgraded.bundledSourceCount, newCatalog.count)
        XCTAssertEqual(upgraded.bookSources, [custom, edited, alreadyImported, newSource])
        XCTAssertEqual(upgraded.bookshelf.first?.sourceUrl, book.sourceUrl)
        XCTAssertEqual(upgraded.getCachedChapter(bookId: book.id, chapterIndex: 0, chapterURL: chapter.chapterURL,
                                                sourceURL: book.sourceUrl), chapter.text)

        upgraded.bookSources.removeAll { $0.id == newSource.id }
        upgraded.saveBookSources()
        let relaunched = StorageManager(defaults: defaults, cacheDirectoryURL: cache, bundledSources: newCatalog)
        XCTAssertEqual(relaunched.bookSources, [custom, edited, alreadyImported])
        XCTAssertEqual(relaunched.loadDefaultSources(), 2)
        XCTAssertEqual(relaunched.bookSources, [custom, edited, alreadyImported, removedLegacy, newSource])
    }

    func testFreshInstallLoadsEntireCatalogButAnEmptySavedListStaysEmpty() throws {
        let (defaults, cache) = try isolatedStorage()
        let catalog = [BookSource(bookSourceName: "内置源", bookSourceUrl: "https://catalog.invalid")]
        let fresh = StorageManager(defaults: defaults, cacheDirectoryURL: cache, bundledSources: catalog)
        XCTAssertEqual(fresh.bookSources, catalog)

        fresh.bookSources.removeAll()
        fresh.saveBookSources()
        let relaunched = StorageManager(defaults: defaults, cacheDirectoryURL: cache, bundledSources: catalog)
        XCTAssertTrue(relaunched.bookSources.isEmpty)
    }
}
