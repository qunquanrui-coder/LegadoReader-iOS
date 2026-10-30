import XCTest
@testable import LegadoReader

final class ReaderAdaptiveLayoutTests: XCTestCase {
    func testManualSpreadFallsBackOnCoverAndSplitWindowAndReturnsOnWideWindow() {
        let wide = CGSize(width: 880, height: 570)
        XCTAssertEqual(ReaderLayoutPolicy.presentation(size: wide, preferred: .duoSpread, autoSpread: false,
                                                       fontSize: 19, spineWidth: 1), .spread)
        for size in [CGSize(width: 390, height: 570), CGSize(width: 310, height: 570)] {
            XCTAssertEqual(ReaderLayoutPolicy.presentation(size: size, preferred: .duoSpread, autoSpread: false,
                                                           fontSize: 19, spineWidth: 1), .page)
        }
        XCTAssertEqual(ReaderLayoutPolicy.presentation(size: wide, preferred: .duoSpread, autoSpread: false,
                                                       fontSize: 19, spineWidth: 1), .spread)
    }

    func testFontAndShortWindowPreventUnreadablySmallColumns() {
        XCTAssertEqual(ReaderLayoutPolicy.presentation(size: CGSize(width: 700, height: 560), preferred: .verticalScroll,
                                                       autoSpread: true, fontSize: 30, spineWidth: 18), .scroll)
        XCTAssertEqual(ReaderLayoutPolicy.presentation(size: CGSize(width: 850, height: 210), preferred: .verticalScroll,
                                                       autoSpread: true, fontSize: 19, spineWidth: 1), .scroll)
    }

    func testExplicitSinglePagePreferenceWithoutAutoSpreadStaysSingle() {
        XCTAssertEqual(ReaderLayoutPolicy.presentation(size: CGSize(width: 900, height: 600), preferred: .horizontalSlide,
                                                       autoSpread: false, fontSize: 19, spineWidth: 1), .page)
    }

    func testRepeatedFoldKeepsAnchorAndRejectsPriorLayoutCompletion() {
        var restoration = ReaderLayoutRestoration()
        let anchor = ReaderTextAnchor(chapterURL: "https://fixture.invalid/chapter/5", paragraphIndex: 72, characterOffset: 180)
        let opening = restoration.begin(anchor)
        let closing = restoration.begin(anchor)
        XCTAssertNil(restoration.finish(opening, chapterURL: anchor.chapterURL))
        XCTAssertEqual(restoration.anchor, anchor)
        XCTAssertEqual(restoration.finish(closing, chapterURL: anchor.chapterURL), anchor)
        XCTAssertNil(restoration.anchor)
    }

    func testChangingChapterOrDismissingCannotRestoreStaleParagraph() {
        var restoration = ReaderLayoutRestoration()
        let id = restoration.begin(ReaderTextAnchor(chapterURL: "old", paragraphIndex: 95))
        XCTAssertNil(restoration.finish(id, chapterURL: "new"))
        restoration.cancel()
        XCTAssertNil(restoration.finish(id, chapterURL: "old"))
    }

    func testOldConfigAndBackupDecodeWithoutSpineSetting() throws {
        let data = try JSONEncoder().encode(ReaderConfig.default)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "showDuoSpine")
        let decoded = try JSONDecoder().decode(ReaderConfig.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.effectiveShowDuoSpine)
    }
}
