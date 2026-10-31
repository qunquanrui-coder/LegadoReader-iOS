import XCTest
@testable import LegadoReader

final class SourceExpressionTests: XCTestCase {
    func testEvaluatesSupportedStringBridgesRegexAndJSONTransforms() {
        let engine = LegadoJSEngine.shared
        let session = LegadoJSSession(sourceIdentifier: "https://fixture.invalid#1")

        let encoded = engine.evaluate(
            script: "var raw = result.trim(); java.put('savedKey', raw); '/search?q=' + java.encodeURI(raw) + '&p=' + page",
            result: "  诡秘之主  ",
            baseUrl: "https://fixture.invalid",
            key: "诡秘之主",
            page: 2,
            session: session
        )
        XCTAssertEqual(encoded, "/search?q=%E8%AF%A1%E7%A7%98%E4%B9%8B%E4%B8%BB&p=2")
        XCTAssertEqual(engine.evaluate(script: "java.get('savedKey')", session: session), "诡秘之主")

        let b64 = engine.evaluate(script: "java.base64Decode(java.base64Encode(result))", result: "第一章 绯红", session: session)
        XCTAssertEqual(b64, "第一章 绯红")

        let md5Full = engine.evaluate(script: "java.md5Encode('abc')", session: session)
        let md5Short = engine.evaluate(script: "java.md5Encode16('abc')", session: session)
        XCTAssertEqual(md5Full?.count, 32)
        XCTAssertEqual(md5Short, String((md5Full ?? "").dropFirst(8).prefix(16)))

        let regexOut = engine.evaluate(
            script: "result.replace(/id=(\\d+)/, '/book/$1.html')",
            result: "https://fixture.invalid?id=4096",
            session: session
        )
        XCTAssertEqual(regexOut, "https://fixture.invalid/book/4096.html")

        let jsonOut = engine.evaluate(
            script: "var obj = JSON.parse(result); obj.book.name + '-' + Math.max(1, parseInt(obj.book.id, 10))",
            result: #"{"book":{"name":"宿命之环","id":"42"}}"#,
            session: session
        )
        XCTAssertEqual(jsonOut, "宿命之环-42")
        XCTAssertNil(session.firstFailure)
    }

    func testSessionsIsolateStoredVariablesAcrossSourcesAndRequests() throws {
        let engine = LegadoJSEngine.shared
        let sourceA = BookSource(bookSourceName: "A", bookSourceUrl: "https://a.invalid")
        let sourceB = BookSource(bookSourceName: "B", bookSourceUrl: "https://b.invalid")

        let outA: String? = engine.withSession(source: sourceA) {
            _ = engine.evaluate(script: "java.put('token', 'secret-a')")
            return engine.evaluate(script: "java.get('token')")
        }
        let outB: String? = engine.withSession(source: sourceB) {
            engine.evaluate(script: "java.get('token')")
        }
        let outANextRequest: String? = engine.withSession(source: sourceA) {
            engine.evaluate(script: "java.get('token')")
        }

        XCTAssertEqual(outA, "secret-a")
        XCTAssertEqual(outB, "", "Variables from source A must never leak into source B")
        XCTAssertEqual(outANextRequest, "", "A finished request session must release its stored variables")
    }

    func testRejectsLoopsDynamicExecutionAndUnsupportedBridgesDeterministically() {
        let engine = LegadoJSEngine.shared
        for disallowed in [
            "while(true) {}",
            "for(var i=0;i<10;i++){}",
            "eval('1+1')",
            "Function('return 1')()",
            "java.ajax('https://fixture.invalid')",
            "window.location"
        ] {
            XCTAssertNotNil(engine.unsupportedReason(script: disallowed), "Must reject: \(disallowed)")
            let session = LegadoJSSession(sourceIdentifier: "https://fixture.invalid#test")
            XCTAssertNil(engine.evaluate(script: disallowed, result: "ok", session: session))
            XCTAssertNotNil(session.firstFailure)
        }
    }

    func testCancelledSessionStopsEvaluationAndThrowsCancellationError() {
        let engine = LegadoJSEngine.shared
        let source = BookSource(bookSourceName: "Cancel", bookSourceUrl: "https://cancel.invalid")
        XCTAssertThrowsError(try engine.withSession(source: source) {
            LegadoJSEngine.currentSession?.cancel()
            _ = engine.evaluate(script: "result.trim()", result: "hello")
            try engine.throwIfSessionFailed()
        }) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testSearchPolicyRejectsCSSPrefixedJavaScriptListAndUnsupportedFieldScripts() {
        XCTAssertTrue(SourceSearchPolicy.supportedSearchListAlternatives("@css:.books@js:result").isEmpty)
        XCTAssertEqual(
            SourceSearchPolicy.supportedSearchListAlternatives("$.data || @css:ul.list li || @js:result"),
            ["ul.list li"]
        )

        let badFieldSource = BookSource(
            bookSourceName: "BadField",
            bookSourceUrl: "https://fixture.invalid",
            searchUrl: "/s?q={{key}}",
            ruleSearch: RuleSearch(
                bookList: ".item",
                name: "a@text@js:while(true){}",
                author: nil,
                intro: nil,
                coverUrl: nil,
                bookUrl: "a@href",
                lastChapter: nil
            )
        )
        XCTAssertNotNil(SourceSearchPolicy.unsupportedReason(badFieldSource))
    }
}
