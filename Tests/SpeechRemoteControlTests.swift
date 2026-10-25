import XCTest
@testable import LegadoReader

final class SpeechRemoteControlTests: XCTestCase {
    @MainActor
    func testRemoteToggleAfterStopCannotReadOldBookUnderNewContext() {
        let speech = SpeechSynthesizerManager.shared
        speech.stop()
        defer { speech.stop(); speech.detachReader() }

        let bookA = Book(title: "A", author: "Author A", sourceUrl: "https://a.invalid",
                         sourceName: "A", bookUrl: "https://a.invalid/book")
        let bookB = Book(title: "B", author: "Author B", sourceUrl: "https://b.invalid",
                         sourceName: "B", bookUrl: "https://b.invalid/book")
        let chaptersA = [Chapter(index: 0, title: "A Chapter", url: "https://a.invalid/chapter")]
        let chaptersB = [Chapter(index: 0, title: "B Chapter", url: "https://b.invalid/chapter")]
        speech.setContext(book: bookA, chapters: chaptersA, chapterIndex: 0)
        // Paused initialization fills the real paragraph buffer without starting any network request.
        speech.startReading(paragraphs: ["Book A's old text"], bookTitle: bookA.title,
                            chapterTitle: chaptersA[0].title, initiallyPaused: true)
        speech.stop()

        // Opening another reader sets context even when the user has not tapped 听书.
        speech.setContext(book: bookB, chapters: chaptersB, chapterIndex: 0)
        speech.updateNowPlayingMetadata(bookTitle: bookB.title, chapterTitle: chaptersB[0].title)
        var changedParagraph = false
        speech.onParagraphChanged = { _ in changedParagraph = true }
        let endedSession = speech.sessionStopCount

        XCTAssertFalse(speech.resumeOrPause(), "AirPods/lock-screen toggle must reject a stopped session")
        XCTAssertFalse(speech.isSpeaking)
        XCTAssertFalse(speech.isLoadingAudio)
        XCTAssertFalse(changedParagraph)
        XCTAssertEqual(speech.context?.book.id, bookB.id)
        XCTAssertEqual(speech.sessionStopCount, endedSession)
    }

    @MainActor
    func testRemoteToggleDuringChapterTransitionCannotRestartOldParagraphs() {
        let speech = SpeechSynthesizerManager.shared
        speech.stop()
        defer { speech.stop(); speech.detachReader() }
        speech.startReading(paragraphs: ["Previous chapter"], initiallyPaused: true)
        speech.setSleepTimer(minutes: 30)
        let session = speech.sessionStopCount
        speech.suspendForChapterTransition()

        XCTAssertFalse(speech.resumeOrPause())
        XCTAssertFalse(speech.isSpeaking)
        XCTAssertEqual(speech.sleepTimerMinutes, 30)
        XCTAssertEqual(speech.sessionStopCount, session)
    }
}
