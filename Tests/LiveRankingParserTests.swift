import XCTest
@testable import LegadoReader

final class LiveRankingParserTests: XCTestCase {
    func testParsesQidianSSRRecordsWithNestedBracketsAndQuotes() {
        let html = """
        <html><body><script>window.__INITIAL__={"rank":{"records":[
          {"bName":"神宠供应商","bAuth":"轻泉流响","bid":"1050460263","cat":"轻小说","subCat":"原生幻想","cnt":"91.07万字","rankCnt":"8.28万月票","desc":"海洋纪元 [测试括号] \\"御兽\\" 冒险。"},
          {"bName":"玄鉴仙族","bAuth":"季越人","bid":1035420986,"cat":"仙侠","subCat":"修真文明","cnt":"656.86万字","rankCnt":"7.43万月票","desc":"家族修仙群像。"}
        ],"more":true}};</script></body></html>
        """
        let books = BookRecommendationEngine.parseQidianRecords(
            from: html,
            defaultCategory: .trending,
            badgeFallback: "起点月票榜"
        )
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].title, "神宠供应商")
        XCTAssertEqual(books[0].author, "轻泉流响")
        XCTAssertEqual(books[0].rating, "8.28万月票")
        XCTAssertEqual(books[0].coverUrl, "https://bookcover.yuewen.com/qdbimg/349573/1050460263/180")
        XCTAssertTrue(books[0].isLive)
        XCTAssertTrue(books[0].tagline.contains("轻小说"))
        XCTAssertEqual(books[1].coverUrl, "https://bookcover.yuewen.com/qdbimg/349573/1035420986/180")
    }

    func testParsesZonghengJSONRankResponse() throws {
        let payload = """
        {
          "code": 0,
          "result": {
            "resultList": [
              {
                "bookName": "无敌天命",
                "pseudonym": "青鸾峰上",
                "cateFineName": "玄幻奇幻",
                "bookCover": "https://static.zongheng.com/upload/cover/test.jpeg",
                "description": "谁言天命天注定？\\n我命由我不由天！",
                "latestChapterName": "第一千九百二十四章",
                "number": 28353
              }
            ]
          }
        }
        """
        let books = BookRecommendationEngine.parseZonghengRank(
            from: Data(payload.utf8),
            defaultCategory: .trending,
            badgeFallback: "纵横月票"
        )
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "无敌天命")
        XCTAssertEqual(books[0].author, "青鸾峰上")
        XCTAssertEqual(books[0].rating, "2.8万热度")
        XCTAssertEqual(books[0].coverUrl, "https://static.zongheng.com/upload/cover/test.jpeg")
        XCTAssertTrue(books[0].isLive)
    }

    func testRemoteCategoryMappingAndCuratedFreshness() {
        XCTAssertEqual(BookRecommendationEngine.mapRemoteCategory("仙侠 · 修真文明", fallback: .xuanhuan), .xianxia)
        XCTAssertEqual(BookRecommendationEngine.mapRemoteCategory("悬疑 · 规则怪谈", fallback: .xuanhuan), .mystery)
        XCTAssertEqual(BookRecommendationEngine.mapRemoteCategory("都市 · 年代", fallback: .xuanhuan), .urban)
        XCTAssertEqual(BookRecommendationEngine.mapRemoteCategory("历史 · 东晋", fallback: .xuanhuan), .historySciFi)

        let engine = BookRecommendationEngine.shared
        for category in NovelCategory.allCases {
            XCTAssertGreaterThanOrEqual(
                engine.books(for: category).count,
                5,
                "Category \(category.rawValue) should always have at least 5 recommended novels"
            )
        }
        XCTAssertEqual(engine.dynamicHotKeywords.count, 12)
        XCTAssertEqual(Set(engine.dynamicHotKeywords).count, 12)
    }
}
