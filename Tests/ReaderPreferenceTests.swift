import XCTest
import CoreGraphics
@testable import LegadoReader

final class ReaderPreferenceTests: XCTestCase {
    func testLegacyConfigKeepsItsTypographyInBothWindowsAndBalancedTaps() throws {
        let data = Data("""
        {"fontSize":23,"lineSpacing":12,"theme":"羊皮卷","fontDesign":"书宋衬线","pageTurnMode":"左右翻页"}
        """.utf8)
        let config = try JSONDecoder().decode(ReaderConfig.self, from: data)
        XCTAssertEqual(config.typography(for: .compact), ReaderTypography(fontSize: 23, lineSpacing: 12))
        XCTAssertEqual(config.typography(for: .wide), ReaderTypography(fontSize: 23, lineSpacing: 12))
        XCTAssertEqual(config.effectiveTapMode, .balanced)
        XCTAssertNil(config.compactTypography)
        XCTAssertNil(config.wideTypography)
    }

    func testEditingOneWindowDoesNotChangeOtherWindowOrLegacyFallback() {
        var config = ReaderConfig.default
        config.fontSize = 21
        config.lineSpacing = 8
        config.setTypography(ReaderTypography(fontSize: 27, lineSpacing: 16), for: .wide)
        XCTAssertEqual(config.typography(for: .compact), ReaderTypography(fontSize: 21, lineSpacing: 8))
        config.setTypography(ReaderTypography(fontSize: 18, lineSpacing: 6), for: .compact)
        XCTAssertEqual(config.typography(for: .wide), ReaderTypography(fontSize: 27, lineSpacing: 16))
        XCTAssertEqual(config.typography(for: .compact), ReaderTypography(fontSize: 18, lineSpacing: 6))
        XCTAssertEqual(config.fontSize, 21)
        XCTAssertEqual(config.lineSpacing, 8)
    }

    func testBothProfilesAndHandednessSurviveConfigBackupRoundTrip() throws {
        var config = ReaderConfig.default
        config.setTypography(ReaderTypography(fontSize: 17, lineSpacing: 6), for: .compact)
        config.setTypography(ReaderTypography(fontSize: 25, lineSpacing: 14), for: .wide)
        config.effectiveTapMode = .leftHanded
        config.theme = .pureBlack
        let decoded = try JSONDecoder().decode(ReaderConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.effectiveTapMode, .leftHanded)
        XCTAssertEqual(decoded.typography(for: .compact).fontSize, 17)
        XCTAssertEqual(decoded.typography(for: .wide).fontSize, 25)
    }

    func testProfileFeedsActualPaginationWithoutChangingGlobalReadingPreferences() {
        var config = ReaderConfig.default
        config.setTypography(ReaderTypography(fontSize: 14, lineSpacing: 4), for: .compact)
        config.setTypography(ReaderTypography(fontSize: 30, lineSpacing: 20), for: .wide)
        config.fontDesign = .rounded
        config.effectiveTapMode = .rightHanded
        let compact = config.applyingTypography(for: .compact)
        let wide = config.applyingTypography(for: .wide)
        let size = CGSize(width: 330, height: 500)
        let paragraphs = [String(repeating: "分别记住字号和行距后，分页必须使用当前窗口的实际偏好。", count: 70)]
        let compactPages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "", style: ReaderPageStyle(config: compact), viewport: size)
        let widePages = ReaderPaginator.paginate(paragraphs: paragraphs, chapterTitle: "", style: ReaderPageStyle(config: wide), viewport: size)
        XCTAssertGreaterThan(widePages.count, compactPages.count)
        XCTAssertEqual(compact.fontDesign, .rounded)
        XCTAssertEqual(wide.effectiveTapMode, .rightHanded)
        XCTAssertEqual(wide.theme, config.theme)
        XCTAssertEqual(config.fontSize, ReaderConfig.default.fontSize)
    }

    func testDecodedOutOfRangeProfileIsNormalizedBeforeRendering() throws {
        var config = ReaderConfig.default
        config.wideTypography = ReaderTypography(fontSize: 20, lineSpacing: 10)
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        data["wideTypography"] = ["fontSize": -100, "lineSpacing": 900]
        let decoded = try JSONDecoder().decode(ReaderConfig.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(decoded.typography(for: .wide), ReaderTypography(fontSize: 8, lineSpacing: 80))
        XCTAssertEqual(ReaderTypography(fontSize: .nan, lineSpacing: .infinity), ReaderTypography(fontSize: 19, lineSpacing: 10))
    }

    func testHandedTapAreasLeaveAnAccessibleMenuAndLargerForwardRegion() {
        XCTAssertEqual(ReaderTapMode.balanced.region(at: 0.1), .backward)
        XCTAssertEqual(ReaderTapMode.balanced.region(at: 0.5), .center)
        XCTAssertEqual(ReaderTapMode.balanced.region(at: 0.9), .forward)
        XCTAssertEqual(ReaderTapMode.rightHanded.region(at: 0.149), .backward)
        XCTAssertEqual(ReaderTapMode.rightHanded.region(at: 0.15), .center)
        XCTAssertEqual(ReaderTapMode.rightHanded.region(at: 0.349), .center)
        XCTAssertEqual(ReaderTapMode.rightHanded.region(at: 0.35), .forward)
        XCTAssertEqual(ReaderTapMode.rightHanded.region(at: 1), .forward)
        XCTAssertEqual(ReaderTapMode.leftHanded.region(at: 0), .forward)
        XCTAssertEqual(ReaderTapMode.leftHanded.region(at: 0.649), .forward)
        XCTAssertEqual(ReaderTapMode.leftHanded.region(at: 0.65), .center)
        XCTAssertEqual(ReaderTapMode.leftHanded.region(at: 0.849), .center)
        XCTAssertEqual(ReaderTapMode.leftHanded.region(at: 0.85), .backward)
        XCTAssertEqual(ReaderTapMode.leftHanded.region(at: 1), .backward)
    }

    func testTapAreaBoundsAndInvalidFractionsAreSafe() {
        XCTAssertEqual(ReaderTapMode.balanced.region(at: -10), .backward)
        XCTAssertEqual(ReaderTapMode.balanced.region(at: 20), .forward)
        for mode in ReaderTapMode.allCases {
            XCTAssertEqual(mode.region(at: .nan), .center)
            XCTAssertEqual(mode.region(at: .infinity), .center)
            XCTAssertEqual(mode.region(at: -.infinity), .center)
        }
    }
}
