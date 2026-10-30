import XCTest
@testable import LegadoReader

final class ReadingPositionTests: XCTestCase {
    private func book(offset: Int? = 0) -> Book {
        Book(title: "精确续读", author: "测试作者", sourceUrl: "https://source.invalid",
             sourceName: "测试源", bookUrl: "https://source.invalid/book/1", currentChapterIndex: 4,
             currentParagraphIndex: 3, currentCharacterOffset: offset)
    }

    func testLegacyBookJSONDecodesMissingCharacterOffsetAsZero() throws {
        let encoded = try JSONEncoder().encode(book(offset: 89))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "currentCharacterOffset")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Book.self, from: legacy)
        XCTAssertEqual(decoded.currentChapterIndex, 4)
        XCTAssertEqual(decoded.currentParagraphIndex, 3)
        XCTAssertEqual(decoded.currentCharacterOffset, 0)
    }

    func testBookJSONPreservesUTF16OffsetAndNormalizesNegativeOffset() throws {
        let original = book(offset: 137)
        let decoded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        var invalid = original
        invalid.currentCharacterOffset = -12
        let sanitized = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(invalid))
        XCTAssertEqual(sanitized.currentCharacterOffset, 0)
    }

    func testPositionMapReadsLegacyPairsAndNewOffsets() {
        XCTAssertEqual(StoredReadingPosition(values: [4, 3]),
                       StoredReadingPosition(chapterIndex: 4, paragraphIndex: 3, characterOffset: 0))
        XCTAssertEqual(StoredReadingPosition(values: [4, 3, 137])?.characterOffset, 137)
        XCTAssertEqual(StoredReadingPosition(values: [4, 3, -137])?.characterOffset, 0)
        XCTAssertNil(StoredReadingPosition(values: [4]))
        XCTAssertEqual(StoredReadingPosition(chapterIndex: 4, paragraphIndex: 3).values, [4, 3])
    }

    func testUserDefaultsRoundTripReopensAtTheSameLongParagraphFragment() throws {
        let suite = "ReaderPositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mapKey = "positions"
        let key = "精确续读_测试作者"
        let writer = ReadingPositionStore(defaults: defaults, key: mapKey)
        writer.set(StoredReadingPosition(chapterIndex: 4, paragraphIndex: 3, characterOffset: 137), for: key)
        // Recreate the store to exercise the property-list representation, not an in-memory anchor.
        let reader = ReadingPositionStore(defaults: defaults, key: mapKey)
        let restored = try XCTUnwrap(reader.position(for: key))
        let pages = [
            ReaderPage(items: [PaginatedParagraph(index: 3, text: "段落开头", characterOffset: 0)]),
            ReaderPage(items: [PaginatedParagraph(index: 3, text: "段落中间", characterOffset: 100)]),
            ReaderPage(items: [PaginatedParagraph(index: 3, text: "段落结尾", characterOffset: 200)])
        ]
        XCTAssertEqual(restored.chapterIndex, 4)
        XCTAssertEqual(ReaderPageLocator.pageIndex(paragraphIndex: restored.paragraphIndex,
                                                 characterOffset: restored.characterOffset, pages: pages), 1)
        XCTAssertEqual((defaults.dictionary(forKey: mapKey) as? [String: [Int]])?[key], [4, 3, 137])

        // The default offset used by paragraph-only callers such as TTS clears an old fragment.
        writer.set(StoredReadingPosition(chapterIndex: 4, paragraphIndex: 4), for: key)
        XCTAssertEqual(reader.position(for: key)?.characterOffset, 0)
        XCTAssertEqual((defaults.dictionary(forKey: mapKey) as? [String: [Int]])?[key], [4, 4])
    }

    func testUserDefaultsReadsLegacyMapAndPreservesOtherBooks() throws {
        let suite = "ReaderPositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["legacy": [7, 8], "invalid": [1]], forKey: "positions")
        let store = ReadingPositionStore(defaults: defaults, key: "positions")
        XCTAssertEqual(store.position(for: "legacy")?.characterOffset, 0)
        XCTAssertNil(store.position(for: "invalid"))
        store.set(StoredReadingPosition(chapterIndex: 3, paragraphIndex: 1, characterOffset: 20), for: "new")
        XCTAssertEqual(store.position(for: "legacy")?.chapterIndex, 7)
        XCTAssertEqual(store.position(for: "legacy")?.paragraphIndex, 8)
    }

    func testSourceReplacementResetsOnlyCharacterOffsetWhenTextIdentityChanges() {
        let original = book(offset: 137)
        var incoming = original
        incoming.sourceUrl = "https://other.invalid"
        incoming.bookUrl = "https://other.invalid/book/9"
        let replaced = StorageManager.bookByReplacingSource(of: original, with: incoming)
        XCTAssertEqual(replaced.id, original.id)
        XCTAssertEqual(replaced.currentChapterIndex, original.currentChapterIndex)
        XCTAssertEqual(replaced.currentParagraphIndex, original.currentParagraphIndex)
        XCTAssertEqual(replaced.currentCharacterOffset, 0)
        XCTAssertEqual(StorageManager.bookByReplacingSource(of: original, with: original).currentCharacterOffset, 137)
    }
}
