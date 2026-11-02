import XCTest
@testable import LegadoReader

final class ExpressiveSpeechTests: XCTestCase {
    func testVoiceRosterIncludesExpressiveAndRegionalActors() {
        XCTAssertEqual(NeuralVoiceActor.allCases.count, 10)
        XCTAssertTrue(NeuralVoiceActor.allCases.contains(.yunxia))
        XCTAssertTrue(NeuralVoiceActor.allCases.contains(.xiaobei))
        XCTAssertTrue(NeuralVoiceActor.allCases.contains(.xiaoni))
        XCTAssertTrue(NeuralVoiceActor.allCases.contains(.hsiaochen))
        XCTAssertTrue(NeuralVoiceActor.allCases.contains(.yunjhe))

        XCTAssertEqual(NeuralVoiceActor.hsiaochen.xmlLang, "zh-TW")
        XCTAssertEqual(NeuralVoiceActor.yunjhe.xmlLang, "zh-TW")
        XCTAssertEqual(NeuralVoiceActor.yunxia.xmlLang, "zh-CN")
        XCTAssertTrue(NeuralVoiceActor.xiaobei.isFemale)
        XCTAssertFalse(NeuralVoiceActor.yunxia.isFemale)
    }

    func testMultiRoleDramaSeparatesNarratorFemaleAndMaleDialogue() {
        let paragraph = "夜色渐深，少女微微蹙眉，轻声说道：“你真的要一个人去吗？”少年握紧长剑，大喝道：“这一战，我绝不退缩！”"
        let turns = ExpressiveSpeechPlanner.plan(
            paragraph: paragraph,
            primaryVoice: .yunxi,
            style: .multiRoleDrama
        )

        XCTAssertEqual(turns.count, 4)
        XCTAssertEqual(turns[0].voice, .yunjian, "Narrator should use storytelling voice when primary is Yunxi")
        XCTAssertEqual(turns[1].voice, .xiaoxiao, "Female dialogue should switch to female actor")
        XCTAssertEqual(turns[2].voice, .yunjian, "Middle narration should return to narrator voice")
        XCTAssertEqual(turns[3].voice, .yunxi, "Male dialogue should use male protagonist voice")

        XCTAssertEqual(turns[1].segments.first?.role, .femaleDialogue)
        XCTAssertEqual(turns[1].segments.first?.emotion, .somberOrWhisper, "Pre-quote '轻声' should imbue whisper prosody")
        XCTAssertEqual(turns[3].segments.first?.role, .maleDialogue)
        XCTAssertEqual(turns[3].segments.first?.emotion, .excitedOrAngry, "Pre-quote '大喝' and '！' should imbue excited prosody")
        XCTAssertGreaterThan(turns[3].segments[0].pitchHz, turns[0].segments[0].pitchHz)
    }

    func testEmotionalSingleVoiceKeepsPrimaryActorWithMultiClauseProsody() {
        let paragraph = "他低声叹了口气……“难道真的没有办法了吗？”随即他猛地抬头怒吼：“给我破开！”"
        let turns = ExpressiveSpeechPlanner.plan(
            paragraph: paragraph,
            primaryVoice: .yunxia,
            style: .emotionalSingleVoice
        )

        XCTAssertEqual(turns.count, 1, "Single-voice emotional style must coalesce all clauses into one voice turn")
        XCTAssertEqual(turns[0].voice, .yunxia)
        XCTAssertGreaterThanOrEqual(turns[0].segments.count, 3)

        let ssml = turns[0].buildSSML(baseRateMultiplier: 1.0)
        XCTAssertTrue(ssml.contains("<voice name='zh-CN-YunxiaNeural'>"))
        XCTAssertTrue(ssml.contains("pitch='-5Hz'"))
        XCTAssertTrue(ssml.contains("pitch='+8Hz'"))
    }

    func testFlatStyleProducesSingleUniformProsodyTurnAndEscapesXML() {
        let paragraph = "測試 <标签> & \"引号\" '单引号'"
        let turns = ExpressiveSpeechPlanner.plan(
            paragraph: paragraph,
            primaryVoice: .hsiaochen,
            style: .flat
        )

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].segments.count, 1)
        XCTAssertEqual(turns[0].segments[0].pitchHz, 0)
        XCTAssertEqual(turns[0].segments[0].rateDeltaPercent, 0)
        XCTAssertEqual(turns[0].segments[0].volumeDeltaPercent, 0)

        let ssml = turns[0].buildSSML(baseRateMultiplier: 1.25)
        XCTAssertTrue(ssml.contains("xml:lang='zh-TW'"))
        XCTAssertTrue(ssml.contains("rate='+25%'"))
        XCTAssertTrue(ssml.contains("&lt;标签&gt; &amp; &quot;引号&quot; &apos;单引号&apos;"))
    }

    func testDialogueRoleDetectionFromFollowingAttributionAndSelfAddress() {
        let roleFromPost = NovelEmotionAnalyzer.detectDialogueRole(
            quoteText: "“不必多言。”",
            precedingNarration: "",
            followingNarration: "少女转身离去。",
            defaultVoice: .yunxi
        )
        XCTAssertEqual(roleFromPost, .femaleDialogue)

        let roleFromSelfAddress = NovelEmotionAnalyzer.detectDialogueRole(
            quoteText: "“老夫纵横江湖数十年，何曾惧过！”",
            precedingNarration: "那人开口道：",
            followingNarration: "",
            defaultVoice: .xiaoxiao
        )
        XCTAssertEqual(roleFromSelfAddress, .maleDialogue)
    }

    @MainActor
    func testSpeechManagerUpdatesExpressiveStyleAndVoice() {
        let store = StorageManager(
            defaults: UserDefaults(suiteName: "ExpressiveSpeechTests_\(UUID().uuidString)")!,
            cacheDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            loadDefaults: false
        )
        let speech = SpeechSynthesizerManager(testing: true, storage: store)
        XCTAssertEqual(speech.expressiveStyle, .multiRoleDrama)

        speech.setExpressiveStyle(.emotionalSingleVoice)
        XCTAssertEqual(speech.expressiveStyle, .emotionalSingleVoice)

        speech.setVoice(.yunxia)
        XCTAssertEqual(speech.selectedVoice, .yunxia)
    }
}
