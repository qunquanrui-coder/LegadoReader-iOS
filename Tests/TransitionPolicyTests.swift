import XCTest
@testable import LegadoReader

final class TocUpdatePolicyTests: XCTestCase {
    func testCompleteRefreshAlwaysReplacesLocalCatalogue() {
        XCTAssertTrue(TocUpdatePolicy.shouldAcceptRefresh(resultComplete: true, localChapterCount: 1000))
        XCTAssertTrue(TocUpdatePolicy.shouldAcceptRefresh(resultComplete: true, localChapterCount: 0))
    }

    func testIncompleteRefreshNeverShrinksAnExistingCatalogue() {
        XCTAssertFalse(TocUpdatePolicy.shouldAcceptRefresh(resultComplete: false, localChapterCount: 1000))
        XCTAssertFalse(TocUpdatePolicy.shouldAcceptRefresh(resultComplete: false, localChapterCount: 1))
    }

    func testIncompleteRefreshIsUsableWhenNothingWasCachedYet() {
        XCTAssertTrue(TocUpdatePolicy.shouldAcceptRefresh(resultComplete: false, localChapterCount: 0))
    }

    func testStaleSourceRequestIsRejected() {
        XCTAssertTrue(TocUpdatePolicy.matchesRequest(currentSourceUrl: "https://a.invalid",
                                                    currentBookUrl: "https://a.invalid/book/1",
                                                    requestedSourceUrl: "https://a.invalid",
                                                    requestedBookUrl: "https://a.invalid/book/1"))
        // Source switched while the TOC request was still running.
        XCTAssertFalse(TocUpdatePolicy.matchesRequest(currentSourceUrl: "https://b.invalid",
                                                     currentBookUrl: "https://b.invalid/book/1",
                                                     requestedSourceUrl: "https://a.invalid",
                                                     requestedBookUrl: "https://a.invalid/book/1"))
        XCTAssertFalse(TocUpdatePolicy.matchesRequest(currentSourceUrl: "https://a.invalid",
                                                     currentBookUrl: "https://a.invalid/book/2",
                                                     requestedSourceUrl: "https://a.invalid",
                                                     requestedBookUrl: "https://a.invalid/book/1"))
    }

    func testFullCacheCompletionAlsoRequiresCompleteCatalogue() {
        XCTAssertTrue(TocUpdatePolicy.isFullCacheComplete(savedCount: 100, totalCount: 100, tocComplete: true))
        XCTAssertFalse(TocUpdatePolicy.isFullCacheComplete(savedCount: 100, totalCount: 100, tocComplete: false))
        XCTAssertFalse(TocUpdatePolicy.isFullCacheComplete(savedCount: 99, totalCount: 100, tocComplete: true))
        XCTAssertFalse(TocUpdatePolicy.isFullCacheComplete(savedCount: 0, totalCount: 0, tocComplete: true))
    }

    func testTocStateResetsWhenSourceIdentityChanges() {
        XCTAssertTrue(TocUpdatePolicy.requiresTocReset(loadedSourceUrl: nil, loadedBookUrl: nil,
                                                       currentSourceUrl: "https://a.invalid",
                                                       currentBookUrl: "https://a.invalid/book/1"))
        // Source switch: the old source's list must be dropped instead of shown for the new one.
        XCTAssertTrue(TocUpdatePolicy.requiresTocReset(loadedSourceUrl: "https://a.invalid",
                                                       loadedBookUrl: "https://a.invalid/book/1",
                                                       currentSourceUrl: "https://b.invalid",
                                                       currentBookUrl: "https://b.invalid/book/1"))
        XCTAssertFalse(TocUpdatePolicy.requiresTocReset(loadedSourceUrl: "https://a.invalid",
                                                        loadedBookUrl: "https://a.invalid/book/1",
                                                        currentSourceUrl: "https://a.invalid",
                                                        currentBookUrl: "https://a.invalid/book/1"))
    }
}

final class PlaybackTransitionPolicyTests: XCTestCase {
    func testListeningRequiresLoadedContentForCurrentChapter() {
        XCTAssertTrue(PlaybackTransitionPolicy.canStartListening(loadedChapterURL: "https://x.invalid/2.html",
                                                                 currentChapterURL: "https://x.invalid/2.html",
                                                                 hasParagraphs: true))
        // New chapter is still loading: formattedParagraphs still belongs to the previous chapter.
        XCTAssertFalse(PlaybackTransitionPolicy.canStartListening(loadedChapterURL: "https://x.invalid/1.html",
                                                                  currentChapterURL: "https://x.invalid/2.html",
                                                                  hasParagraphs: true))
        XCTAssertFalse(PlaybackTransitionPolicy.canStartListening(loadedChapterURL: nil,
                                                                  currentChapterURL: "https://x.invalid/2.html",
                                                                  hasParagraphs: true))
        XCTAssertFalse(PlaybackTransitionPolicy.canStartListening(loadedChapterURL: "https://x.invalid/2.html",
                                                                  currentChapterURL: "https://x.invalid/2.html",
                                                                  hasParagraphs: false))
    }

    func testResumeRequiresBothCarryOverAndStillPending() {
        XCTAssertTrue(PlaybackTransitionPolicy.shouldResume(carryOverRequested: true,
                                                            carryOverPending: true,
                                                            hasParagraphs: true,
                                                            sessionUnchanged: true))
    }

    func testUserStoppingDuringLoadCancelsResume() {
        XCTAssertFalse(PlaybackTransitionPolicy.shouldResume(carryOverRequested: true,
                                                             carryOverPending: false,
                                                             hasParagraphs: true,
                                                             sessionUnchanged: true))
    }

    func testEndedSessionCancelsResume() {
        XCTAssertFalse(PlaybackTransitionPolicy.shouldResume(carryOverRequested: true,
                                                             carryOverPending: true,
                                                             hasParagraphs: true,
                                                             sessionUnchanged: false))
    }

    func testMissingParagraphsCancelsResume() {
        XCTAssertFalse(PlaybackTransitionPolicy.shouldResume(carryOverRequested: true,
                                                             carryOverPending: true,
                                                             hasParagraphs: false,
                                                             sessionUnchanged: true))
    }
}

final class SpeechTransitionTests: XCTestCase {
    func testChapterTransitionKeepsSleepTimerWhileFullStopCancelsIt() {
        let speech = SpeechSynthesizerManager.shared
        speech.stop()
        speech.setSleepTimer(minutes: 30)
        XCTAssertEqual(speech.sleepTimerMinutes, 30)
        let sessionBefore = speech.sessionStopCount

        speech.suspendForChapterTransition()
        XCTAssertEqual(speech.sleepTimerMinutes, 30,
                       "a chapter switch must not cancel the sleep timer")
        XCTAssertFalse(speech.isSpeaking)
        XCTAssertEqual(speech.sessionStopCount, sessionBefore,
                       "a chapter switch must not end the listening session")

        speech.stop()
        XCTAssertNil(speech.sleepTimerMinutes)
        XCTAssertEqual(speech.sessionStopCount, sessionBefore + 1)
    }

    func testUserStopDuringLoadInvalidatesPendingSession() {
        let speech = SpeechSynthesizerManager.shared
        speech.stop()
        let captured = speech.sessionStopCount
        speech.stop()
        XCTAssertNotEqual(speech.sessionStopCount, captured,
                          "a full stop must invalidate a pending chapter-switch resume")
    }
}
