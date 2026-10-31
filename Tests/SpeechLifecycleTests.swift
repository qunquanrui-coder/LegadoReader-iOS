import XCTest
import AVFoundation
@testable import LegadoReader

final class SpeechLifecycleTests: XCTestCase {
    @MainActor
    func testQueuedOldParagraphCannotCallNewReadersCallback() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let first = fixture.seedBook()
        fixture.speech.setContext(book: first, chapters: chapters(for: first), chapterIndex: 0)
        fixture.speech.startReading(paragraphs: ["Old queued callback"])
        let second = fixture.seedBook(title: "New reader")
        fixture.speech.setContext(book: second, chapters: chapters(for: second), chapterIndex: 0)
        fixture.speech.startReading(paragraphs: ["New paused content"], initiallyPaused: true)
        var callbacks = 0
        fixture.speech.onParagraphChanged = { _ in callbacks += 1 }
        await flushMainQueue()
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(fixture.speech.context?.book.id, second.id)
        XCTAssertTrue(fixture.speech.isPaused)
    }

    @MainActor
    func testDeletingSpeakingBookDropsQueuedParagraphCallbackAndPersistentProgress() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let book = fixture.seedBook()
        fixture.speech.setContext(book: book, chapters: chapters(for: book), chapterIndex: 0)
        let token = try XCTUnwrap(fixture.speech.context?.writeToken)
        var callbacks = 0
        fixture.speech.onParagraphChanged = { _ in callbacks += 1 }
        fixture.speech.startReading(paragraphs: ["A queued paragraph must not resurrect a deleted book."])
        fixture.storage.removeBookFromShelf(book)
        await flushMainQueue()

        XCTAssertFalse(fixture.speech.isSpeaking)
        XCTAssertNil(fixture.speech.context)
        XCTAssertEqual(callbacks, 0)
        XCTAssertFalse(fixture.storage.acceptsBookWrite(token))
        XCTAssertTrue(fixture.storage.bookshelf.isEmpty)
        XCTAssertNil(fixture.defaults.dictionary(forKey: "LegadoReader_PositionMap_v3_1")?[StorageManager.bookKey(title: book.title, author: book.author)])
    }

    @MainActor
    func testDeletedThenReaddedBookRejectsLateDetachedChapterAndCache() async throws {
        let gate = DelayedChapter(started: expectation(description: "chapter request started"))
        let fixture = try Fixture(chapterLoader: { _, _, _, _ in try await gate.load() })
        defer { fixture.close() }
        let book = fixture.seedBook()
        let list = chapters(for: book)
        fixture.speech.setContext(book: book, chapters: list, chapterIndex: 0)
        fixture.speech.startReading(paragraphs: ["Current chapter"], initiallyPaused: true)
        fixture.speech.skipNext()
        await fulfillment(of: [gate.started], timeout: 5)
        let oldTask = try XCTUnwrap(fixture.speech.detachedAdvanceTask)
        let oldToken = try XCTUnwrap(fixture.speech.context?.writeToken)

        fixture.storage.removeBookFromShelf(book)
        _ = fixture.storage.addBookToShelf(book)
        XCTAssertFalse(fixture.storage.acceptsBookWrite(oldToken))
        gate.complete(CompleteChapterContent(text: "Late chapter", chapterURL: list[1].url,
                                             sourceURL: book.sourceUrl, pageCount: 1))
        await oldTask.value
        await flushMainQueue()

        XCTAssertFalse(fixture.speech.isSpeaking)
        XCTAssertNil(fixture.speech.context)
        XCTAssertNil(fixture.storage.getCachedChapter(bookId: book.id, chapterIndex: 1,
                                                       chapterURL: list[1].url, sourceURL: book.sourceUrl))
        XCTAssertEqual(fixture.storage.getSavedReadingPosition(for: book).chapterIndex, 0)
        XCTAssertTrue(fixture.storage.acceptsBookWrite(fixture.storage.bookWriteToken(for: book)))
    }

    @MainActor
    func testOldDetachedLoadCannotReplaceAnotherBooksContextOrLoadingState() async throws {
        let gate = DelayedChapter(started: expectation(description: "old request started"))
        let fixture = try Fixture(chapterLoader: { _, _, _, _ in try await gate.load() })
        defer { fixture.close() }
        let bookA = fixture.seedBook()
        let listA = chapters(for: bookA)
        fixture.speech.setContext(book: bookA, chapters: listA, chapterIndex: 0)
        fixture.speech.startReading(paragraphs: ["A"], initiallyPaused: true)
        fixture.speech.skipNext()
        await fulfillment(of: [gate.started], timeout: 5)
        let oldTask = try XCTUnwrap(fixture.speech.detachedAdvanceTask)

        let bookB = fixture.seedBook(title: "Another book")
        fixture.speech.setContext(book: bookB, chapters: chapters(for: bookB), chapterIndex: 0)
        fixture.speech.startReading(paragraphs: ["B"], initiallyPaused: true)
        fixture.speech.isLoadingAudio = true
        gate.complete(CompleteChapterContent(text: "A late text", chapterURL: listA[1].url,
                                             sourceURL: bookA.sourceUrl, pageCount: 1))
        await oldTask.value

        XCTAssertEqual(fixture.speech.context?.book.id, bookB.id)
        XCTAssertTrue(fixture.speech.isSpeaking)
        XCTAssertTrue(fixture.speech.isPaused)
        XCTAssertTrue(fixture.speech.isLoadingAudio, "An old completion must not clear the new request's UI state")
        XCTAssertNil(fixture.storage.getCachedChapter(bookId: bookA.id, chapterIndex: 1,
                                                       chapterURL: listA[1].url, sourceURL: bookA.sourceUrl))
    }

    @MainActor
    func testInterruptionDoesNotResumeAnAlreadyManuallyPausedSession() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.speech.startReading(paragraphs: ["Paused"], initiallyPaused: true)
        send(.began, to: fixture.speech)
        send(.ended, shouldResume: true, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isSpeaking)
        XCTAssertTrue(fixture.speech.isPaused)
    }

    @MainActor
    func testInterruptionResumesOnlyThePlayingSessionOnce() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.speech.startReading(paragraphs: ["Playing"])
        send(.began, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isPaused)
        send(.ended, shouldResume: true, to: fixture.speech)
        XCTAssertFalse(fixture.speech.isPaused)
        XCTAssertTrue(fixture.speech.pauseByUser())
        send(.ended, shouldResume: true, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isPaused, "Duplicate old notifications must not grant new play permission")
    }

    @MainActor
    func testManualPauseDuringInterruptionCancelsAutomaticResume() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.speech.startReading(paragraphs: ["Playing"])
        send(.began, to: fixture.speech)
        XCTAssertTrue(fixture.speech.pauseByUser(), "Pausing an already interrupted session still records user intent")
        send(.ended, shouldResume: true, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isPaused)
    }

    @MainActor
    func testStopAndNewPausedSessionRejectOldInterruptionResume() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.speech.startReading(paragraphs: ["Old playing session"])
        send(.began, to: fixture.speech)
        fixture.speech.stop()
        fixture.speech.startReading(paragraphs: ["New deliberately paused session"], initiallyPaused: true)
        send(.ended, shouldResume: true, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isPaused)
        XCTAssertTrue(fixture.speech.isSpeaking)
    }

    @MainActor
    func testInterruptionWithoutSystemResumePermissionConsumesEligibility() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.speech.startReading(paragraphs: ["Playing"])
        send(.began, to: fixture.speech)
        send(.ended, shouldResume: false, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isPaused)
        send(.ended, shouldResume: true, to: fixture.speech)
        XCTAssertTrue(fixture.speech.isPaused)
    }

    @MainActor
    func testRemovingDifferentBookDoesNotStopCurrentListener() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let playing = fixture.seedBook()
        let other = fixture.seedBook(title: "Other")
        fixture.speech.setContext(book: playing, chapters: chapters(for: playing), chapterIndex: 0)
        fixture.speech.startReading(paragraphs: ["Playing"], initiallyPaused: true)
        fixture.storage.removeBookFromShelf(other)
        XCTAssertTrue(fixture.speech.isSpeaking)
        XCTAssertEqual(fixture.speech.context?.book.id, playing.id)
    }

    @MainActor
    private func send(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false,
                      to speech: SpeechSynthesizerManager) {
        speech.handleAudioInterruption(Notification(name: AVAudioSession.interruptionNotification,
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue,
                       AVAudioSessionInterruptionOptionKey: shouldResume ? AVAudioSession.InterruptionOptions.shouldResume.rawValue : 0]))
    }

    private func chapters(for book: Book) -> [Chapter] {
        [Chapter(index: 0, title: "Chapter 1", url: book.bookUrl + "/1"),
         Chapter(index: 1, title: "Chapter 2", url: book.bookUrl + "/2")]
    }

    @MainActor
    private func flushMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private final class DelayedChapter {
        let started: XCTestExpectation
        private var continuation: CheckedContinuation<CompleteChapterContent, Error>?
        init(started: XCTestExpectation) { self.started = started }
        func load() async throws -> CompleteChapterContent {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        func complete(_ value: CompleteChapterContent) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    @MainActor
    private final class ListenerBox { weak var speech: SpeechSynthesizerManager? }

    @MainActor
    private final class Fixture {
        let defaults: UserDefaults
        let directory: URL
        let storage: StorageManager
        let speech: SpeechSynthesizerManager
        private let suite: String
        init(chapterLoader: SpeechSynthesizerManager.ChapterLoader? = nil) throws {
            suite = "SpeechLifecycleTests.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
            let box = ListenerBox()
            storage = StorageManager(defaults: defaults, cacheDirectoryURL: directory,
                                     loadDefaults: false, onBookRemoval: { book in _ = box.speech?.stopIfReading(book: book) })
            speech = SpeechSynthesizerManager(testing: true, storage: storage, chapterLoader: chapterLoader)
            box.speech = speech
        }
        @discardableResult
        func seedBook(title: String = "Listening book") -> Book {
            storage.addBookToShelf(Book(title: title, author: "Author", sourceUrl: "https://fixture.invalid",
                                       sourceName: "Fixture", bookUrl: "https://fixture.invalid/\(title)"))
        }
        func close() {
            speech.stop()
            speech.detachReader()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
