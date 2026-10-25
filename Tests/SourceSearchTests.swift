import XCTest
@testable import LegadoReader

private func source(_ index: Int, list: String = ".books") -> BookSource {
    BookSource(bookSourceName: "Source \(index)", bookSourceUrl: "https://fixture.invalid/\(index)",
               searchUrl: "/search?q={{key}}",
               ruleSearch: RuleSearch(bookList: list, name: "a@text", author: nil, intro: nil,
                                      coverUrl: nil, bookUrl: "a@href", lastChapter: nil))
}

private func book(_ title: String = "诡秘之主", author: String = "爱潜水的乌贼", source index: Int = 0) -> Book {
    Book(title: title, author: author, sourceUrl: source(index).bookSourceUrl,
         sourceName: "Source \(index)", bookUrl: "https://fixture.invalid/\(index)/book")
}

private actor RequestProbe {
    var active = 0
    var maximum = 0
    var count = 0
    func begin() { active += 1; count += 1; maximum = max(maximum, active) }
    func end() { active -= 1 }
    func snapshot() -> (Int, Int) { (count, maximum) }
}

private actor DelayedSearch {
    var continuation: CheckedContinuation<[Book], Never>?
    var returned = false
    func wait() async -> [Book] {
        let value = await withCheckedContinuation { continuation = $0 }
        returned = true
        return value
    }
    func pending() -> Bool { continuation != nil }
    func didReturn() -> Bool { returned }
    func release() { continuation?.resume(returning: [book("旧结果")]); continuation = nil }
}

final class SourceSearchTests: XCTestCase {
    @MainActor
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for controlled search")
        throw URLError(.timedOut)
    }

    @MainActor
    func testSearchFindsSourceBeyondFirst35WithBoundedConcurrency() async throws {
        let probe = RequestProbe()
        let session = SourceSearchSession { src, _ in
            await probe.begin()
            try await Task.sleep(nanoseconds: 2_000_000)
            await probe.end()
            return src.bookSourceUrl == source(39).bookSourceUrl ? [book(source: 39)] : []
        }
        session.start(keyword: "诡秘之主", sources: (0..<40).map { source($0) })
        try await waitUntil { !session.isSearching }
        XCTAssertEqual(session.results.count, 1)
        XCTAssertEqual(session.finished, 40)
        XCTAssertEqual(session.emptyResults, 39)
        XCTAssertFalse(session.hasMore)
        let stats = await probe.snapshot()
        XCTAssertEqual(stats.0, 40)
        XCTAssertLessThanOrEqual(stats.1, 6)
    }

    @MainActor
    func testContinueSearchReachesRemainingSourcesWithoutDuplicates() async throws {
        let session = SourceSearchSession(batchSize: 2, concurrency: 2) { src, _ in
            [book(source: Int(src.bookSourceUrl.split(separator: "/").last!)!)]
        }
        session.start(keyword: "诡秘之主", sources: (0..<4).map { source($0) })
        try await waitUntil { !session.isSearching }
        XCTAssertEqual(session.results.count, 2)
        XCTAssertTrue(session.hasMore)
        session.continueSearch()
        try await waitUntil { !session.isSearching }
        XCTAssertEqual(session.results.count, 4)
        XCTAssertEqual(session.finished, 4)
        XCTAssertFalse(session.hasMore)
    }

    @MainActor
    func testSourceVariantsKeepDistinctRowIdentityWithoutChangingPersistedBookID() async throws {
        let originalSource = source(0)
        var alternateSource = originalSource
        alternateSource.bookSourceUrl += "#alternate-rules"
        let originalBook = book()
        let session = SourceSearchSession { src, _ in
            var candidate = originalBook
            candidate.sourceUrl = src.bookSourceUrl
            // Duplicate rows within one source collapse; distinct rule variants stay selectable.
            return [candidate, candidate]
        }
        session.start(keyword: originalBook.title, sources: [originalSource, alternateSource])
        try await waitUntil { !session.isSearching }
        XCTAssertEqual(session.results.count, 2)
        XCTAssertEqual(Set(session.results.map(\.searchResultID)).count, 2)
        XCTAssertEqual(Set(session.results.map(\.sourceUrl)), Set([originalSource.bookSourceUrl, alternateSource.bookSourceUrl]))
        XCTAssertTrue(session.results.allSatisfy { $0.id == originalBook.id && $0.bookUrl == originalBook.bookUrl })
    }

    @MainActor
    func testOldQueryCannotOverwriteNewQueryEvenWhenTransportIgnoresCancellation() async throws {
        let gate = DelayedSearch()
        let session = SourceSearchSession { _, key in
            if key == "旧" { return await gate.wait() }
            return [book("新结果")]
        }
        session.start(keyword: "旧", sources: [source(0)])
        try await waitUntil { await gate.pending() }
        session.start(keyword: "新", sources: [source(0)])
        try await waitUntil { !session.isSearching }
        await gate.release()
        try await waitUntil { await gate.didReturn() }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(session.results.map(\.title), ["新结果"])
        XCTAssertEqual(session.finished, 1)
    }

    @MainActor
    func testClearPreventsLateResultsFromReappearing() async throws {
        let gate = DelayedSearch()
        let session = SourceSearchSession { _, _ in await gate.wait() }
        session.start(keyword: "旧", sources: [source(0)])
        try await waitUntil { await gate.pending() }
        session.clear()
        await gate.release()
        try await waitUntil { await gate.didReturn() }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(session.results.isEmpty)
        XCTAssertEqual(session.status, "")
        XCTAssertFalse(session.isSearching)
    }

    @MainActor
    func testReportsFailedEmptyAndUnsupportedSourcesSeparately() async throws {
        let session = SourceSearchSession { src, _ in
            if src.bookSourceUrl == source(0).bookSourceUrl { throw URLError(.badServerResponse) }
            return []
        }
        session.start(keyword: "test", sources: [source(0), source(1), source(2, list: "$.data")])
        try await waitUntil { !session.isSearching }
        XCTAssertEqual(session.failures, 1)
        XCTAssertEqual(session.emptyResults, 1)
        XCTAssertEqual(session.unsupported, 1)
        XCTAssertEqual(session.finished, 2)
    }

    @MainActor
    func testSourceSwitchKeepsCorrectBookEvenWhenNotFirstInResponse() async throws {
        let target = book()
        let correct = book(source: 2)
        let session = SourceSearchSession { _, _ in
            [book("诡秘之主同人"), book(author: "其他作者"), correct]
        }
        session.start(keyword: target.title, sources: [source(2)], matching: target)
        try await waitUntil { !session.isSearching }
        XCTAssertEqual(session.results, [correct])
    }

    func testUnknownAuthorNeedsConfirmationAndSimilarTitleIsRejected() {
        XCTAssertFalse(SourceSearchPolicy.isCandidate(book("诡秘之主同人"), for: book()))
        XCTAssertFalse(SourceSearchPolicy.isCandidate(book(author: "其他作者"), for: book()))
        XCTAssertTrue(SourceSearchPolicy.isCandidate(book("《诡秘之主》"), for: book()))
        let unknown = book(author: "佚名")
        XCTAssertTrue(SourceSearchPolicy.isCandidate(unknown, for: book()))
        XCTAssertTrue(SourceSearchPolicy.needsAuthorConfirmation(unknown, for: book()))
        XCTAssertFalse(SourceSearchPolicy.needsAuthorConfirmation(book(), for: book()))
    }

    func testUnsupportedListRulesAreNotAdvertisedAsSearchable() {
        for rule in ["$.data", "$..books[*]", "<js>java.getElements('a')</js>", "@js:result", "//div/a"] {
            XCTAssertNotNil(SourceSearchPolicy.unsupportedReason(source(0, list: rule)))
        }
        XCTAssertNil(SourceSearchPolicy.unsupportedReason(source(0, list: "class.books@tag.li")))
    }

    func testHTTP403And404AreFailuresNotEmptySuccessfulSearches() throws {
        for code in [403, 404, 500] {
            let response = HTTPURLResponse(url: URL(string: "https://fixture.invalid")!, statusCode: code,
                                           httpVersion: nil, headerFields: nil)!
            XCTAssertThrowsError(try NetworkManager.validateSearchResponse(response))
        }
        let response = HTTPURLResponse(url: URL(string: "https://fixture.invalid")!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        XCTAssertNoThrow(try NetworkManager.validateSearchResponse(response))
    }

    func testImportUpdatesRulesPreservesDisableAndInvalidatesOldTiming() {
        var local = source(0)
        local.enabled = false; local.respondTime = 15
        var updated = source(0)
        updated.searchUrl = "/new-search?q={{key}}"
        let report = SourceImportPolicy.merge(existing: [local], incoming: [updated, source(1)], updateExisting: true)
        XCTAssertEqual(report.added, 1)
        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(report.sources[0].searchUrl, updated.searchUrl)
        XCTAssertEqual(report.sources[0].enabled, false)
        XCTAssertNil(report.sources[0].respondTime)
        let skipped = SourceImportPolicy.merge(existing: [local], incoming: [updated], updateExisting: false)
        XCTAssertEqual(skipped.sources, [local])
        XCTAssertEqual(skipped.skipped, 1)
    }

    func testMalformedImportDoesNotDiscardTheFollowingValidSource() throws {
        let data = Data("""
        [null, {"bookSourceName": 123}, {"bookSourceName":"valid", "bookSourceUrl":"https://fixture.invalid"},
         42, {"bookSourceName":"second", "bookSourceUrl":"https://second.invalid"}]
        """.utf8)
        let decoded = try JSONDecoder().decode(LossyCodableList<BookSource>.self, from: data)
        XCTAssertEqual(decoded.elements.map(\.bookSourceName), ["valid", "second"])
    }

    func testValidationRequiresSearchResultsAndNeverEnablesDisabledSources() async throws {
        var disabled = source(2); disabled.enabled = false
        let tested = try await SourceValidationPolicy.validate(sources: [source(0), source(1), disabled], search: { src, _ in
            if src.bookSourceUrl == source(2).bookSourceUrl { XCTFail("Disabled source was requested") }
            return src.bookSourceUrl == source(0).bookSourceUrl ? [book()] : []
        })
        XCTAssertLessThan(tested.first { $0.bookSourceUrl == source(0).bookSourceUrl }!.respondTime!, 90000)
        XCTAssertEqual(tested.first { $0.bookSourceUrl == source(1).bookSourceUrl }!.respondTime, 99999)
        XCTAssertEqual(tested.first { $0.bookSourceUrl == disabled.bookSourceUrl }!.enabled, false)
    }

    func testValidationMergePreservesLiveImportsDeletionsRulesAndToggles() {
        let original = [source(0), source(1), source(2)]
        var tested = original
        for i in tested.indices { tested[i].respondTime = 10 }
        var disabled = source(0); disabled.enabled = false
        var edited = source(1); edited.searchUrl = "/changed"
        let live = [disabled, edited, source(3)] // Source 2 deleted; source 3 newly imported.
        let merged = SourceValidationPolicy.applying(tested, original: original, to: live)
        XCTAssertEqual(Set(merged.map(\.bookSourceUrl)), Set(live.map(\.bookSourceUrl)))
        XCTAssertEqual(merged.first { $0.bookSourceUrl == disabled.bookSourceUrl }!.enabled, false)
        XCTAssertEqual(merged.first { $0.bookSourceUrl == edited.bookSourceUrl }!, edited)
        XCTAssertTrue(merged.contains(source(3)))
    }
}
