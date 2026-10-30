import XCTest
import CoreGraphics
@testable import LegadoReader

final class DuoReadingFlowTests: XCTestCase {
    func testLongFirstParagraphReopensAtItsSavedFragmentAcrossWindowProfiles() throws {
        let suite = "DuoReadingFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReadingPositionStore(defaults: defaults, key: "positions")
        var config = ReaderConfig.default
        config.setTypography(ReaderTypography(fontSize: 18, lineSpacing: 6), for: .wide)
        config.setTypography(ReaderTypography(fontSize: 25, lineSpacing: 14), for: .compact)
        let paragraphs = [String(repeating: "长段落的中间位置需要跨重启和窗口切换保留。👩🏽‍💻", count: 100), "章节结尾。"]
        let wideSize = CGSize(width: 360, height: 430)
        let wide = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "第一章",
            style: ReaderPageStyle(config: config.applyingTypography(for: .wide)), viewport: wideSize)
        XCTAssertGreaterThan(wide.count, 5)
        let fragment = try XCTUnwrap(wide[4].items.first)
        XCTAssertEqual(fragment.index, 0)
        XCTAssertGreaterThan(fragment.characterOffset, 0)
        store.set(StoredReadingPosition(chapterIndex: 8, paragraphIndex: fragment.index,
                                       characterOffset: fragment.characterOffset), for: "book")
        let reopened = try XCTUnwrap(ReadingPositionStore(defaults: defaults, key: "positions").position(for: "book"))
        XCTAssertEqual(ReaderPageLocator.pageIndex(paragraphIndex: reopened.paragraphIndex,
            characterOffset: reopened.characterOffset, pages: wide), 4)

        let compact = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "第一章",
            style: ReaderPageStyle(config: config.applyingTypography(for: .compact)),
            viewport: CGSize(width: 280, height: 430))
        let relocated = ReaderPageLocator.pageIndex(paragraphIndex: reopened.paragraphIndex,
            characterOffset: reopened.characterOffset, pages: compact)
        let item = try XCTUnwrap(compact[relocated].items.first(where: { $0.index == reopened.paragraphIndex }))
        XCTAssertLessThanOrEqual(item.characterOffset, reopened.characterOffset)
        XCTAssertGreaterThan(item.characterOffset + item.text.utf16.count, reopened.characterOffset)
    }

    func testWindowTypographyDoesNotOscillateWhenLargeFontRequiresSinglePage() {
        var config = ReaderConfig.default
        config.setTypography(ReaderTypography(fontSize: 34, lineSpacing: 20), for: .wide)
        config.setTypography(ReaderTypography(fontSize: 16, lineSpacing: 6), for: .compact)
        let size = CGSize(width: 700, height: 550)
        let profile = ReaderLayoutPolicy.typographyProfile(availableWidth: size.width)
        XCTAssertEqual(profile, .wide)
        let font = config.typography(for: profile).fontSize
        XCTAssertEqual(ReaderLayoutPolicy.presentation(size: size, preferred: .duoSpread,
            autoSpread: true, fontSize: font, spineWidth: 1), .page)
        XCTAssertEqual(config.typography(for: ReaderLayoutPolicy.typographyProfile(availableWidth: size.width)).fontSize, 34)
        XCTAssertEqual(ReaderLayoutPolicy.typographyProfile(availableWidth: 390), .compact)
        XCTAssertEqual(ReaderLayoutPolicy.typographyProfile(availableWidth: .nan), .compact)
    }
}
