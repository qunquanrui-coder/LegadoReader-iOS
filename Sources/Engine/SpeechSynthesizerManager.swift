import Foundation
import AVFoundation
import MediaPlayer
import Combine
#if canImport(UIKit)
import UIKit
#endif

public final class SpeechSynthesizerManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    public static let shared = SpeechSynthesizerManager()
    
    @Published public var isSpeaking: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var isLoadingAudio: Bool = false
    @Published public var currentParagraphIndex: Int = 0
    @Published public var speechRateMultiplier: Float = 1.0
    @Published public var selectedVoice: NeuralVoiceActor = .yunxi
    @Published public var sleepTimerMinutes: Int? = nil
    /// Incremented by every full `stop()`. Async chapter-load completions compare this value
    /// against the one captured when the switch started, so a stop during loading (including
    /// lock-screen / remote-control stop) suppresses the automatic resume.
    @Published public private(set) var sessionStopCount: Int = 0
    
    public var onParagraphChanged: ((Int) -> Void)?
    public var onChapterFinished: (() -> Void)?
    
    @Published public private(set) var currentBookTitle: String = "风读小说"
    @Published public private(set) var currentChapterTitle: String = "正在朗读"
    
    /// Book / TOC / chapter currently being read aloud.
    /// Lets the engine keep advancing chapters on its own after the reader page is closed.
    public struct ReadingContext {
        public var book: Book
        public var chapters: [Chapter]
        public var chapterIndex: Int
        public let writeToken: BookWriteToken
    }
    @Published public private(set) var context: ReadingContext?
    private(set) var detachedAdvanceTask: Task<Void, Never>?
    private let storage: StorageManager
    private let usesSystemAudio: Bool
    typealias ChapterLoader = (Chapter, BookSource, String, String?) async throws -> CompleteChapterContent
    private let chapterLoader: ChapterLoader
    private var playbackID = UUID()
    private var paragraphWorkID = UUID()
    private var interruptionPolicy = SpeechInterruptionPolicy()

    private struct WorkToken {
        let playback: UUID
        let paragraph: UUID
        let stopCount: Int
        let contextIdentity: String?
        let bookWrite: BookWriteToken?
    }

    private static func identity(_ context: ReadingContext?) -> String? {
        guard let context else { return nil }
        let chapterURL = context.chapters.indices.contains(context.chapterIndex)
            ? context.chapters[context.chapterIndex].url : ""
        return [context.book.id, context.book.sourceUrl, context.book.bookUrl,
                String(context.chapterIndex), chapterURL].joined(separator: "\n")
    }

    private func workToken() -> WorkToken {
        WorkToken(playback: playbackID, paragraph: paragraphWorkID, stopCount: sessionStopCount,
                  contextIdentity: Self.identity(context), bookWrite: context?.writeToken)
    }

    private func accepts(_ token: WorkToken) -> Bool {
        token.playback == playbackID && token.paragraph == paragraphWorkID
            && token.stopCount == sessionStopCount && token.contextIdentity == Self.identity(context)
            && (token.bookWrite.map { storage.acceptsBookWrite($0) } ?? true)
    }
    
    public func setContext(book: Book, chapters: [Chapter], chapterIndex: Int) {
        guard chapters.indices.contains(chapterIndex) else { return }
        if let old = context, old.book.id == book.id, old.book.sourceUrl == book.sourceUrl,
           old.book.bookUrl == book.bookUrl, old.chapterIndex == chapterIndex,
           old.chapters.indices.contains(chapterIndex), old.chapters[chapterIndex].url == chapters[chapterIndex].url {
            // Retain the original write generation: deletion/re-addition must not revive this session.
            context = ReadingContext(book: book, chapters: chapters, chapterIndex: chapterIndex,
                                     writeToken: old.writeToken)
            return
        }
        if context != nil {
            if isSpeaking { stop() }
            else {
                detachedAdvanceTask?.cancel()
                detachedAdvanceTask = nil
                stopCurrentPlaybackOnly()
            }
        }
        context = ReadingContext(book: book, chapters: chapters, chapterIndex: chapterIndex,
                                 writeToken: storage.bookWriteToken(for: book))
    }

    /// Called before a book is removed. Stop its detached work as well as the visible player.
    @discardableResult
    public func stopIfReading(book: Book) -> Bool {
        guard let current = context?.book,
              current.id == book.id || (current.title == book.title && current.author == book.author) else { return false }
        stop()
        context = nil
        detachReader()
        return true
    }
    
    /// Called by the reader page when it is closed: callbacks referencing the closed page are dropped,
    /// and the engine continues on its own using `context`.
    public func detachReader() {
        onParagraphChanged = nil
        onChapterFinished = nil
    }
    
    /// Remote controls can toggle an active session, but cannot start a stopped session's old text.
    @discardableResult
    public func resumeOrPause() -> Bool {
        guard isSpeaking, !paragraphs.isEmpty else { return false }
        togglePlayPause(paragraphs: paragraphs, currentIndex: currentParagraphIndex)
        return true
    }
    
    private func handleChapterFinished(token: WorkToken? = nil) {
        guard isSpeaking, token.map({ accepts($0) }) ?? true else { return }
        renewBackgroundTaskAssertion()
        startKeepAliveAudio()
        if let callback = onChapterFinished {
            callback()
        } else {
            advanceChapterDetached()
        }
    }
    
    private func saveDetachedProgress(paragraphIndex: Int) {
        guard isSpeaking, let ctx = context, ctx.chapters.indices.contains(ctx.chapterIndex),
              storage.acceptsBookWrite(ctx.writeToken) else { return }
        storage.updateBookProgress(
            bookId: ctx.book.id,
            bookTitle: ctx.book.title,
            bookAuthor: ctx.book.author,
            chapterIndex: ctx.chapterIndex,
            chapterTitle: ctx.chapters[ctx.chapterIndex].title,
            totalChapters: ctx.chapters.count,
            paragraphIndex: paragraphIndex,
            writeToken: ctx.writeToken
        )
    }
    
    /// Loads the next chapter (cache first, then network) and continues reading — no reader page required
    private func advanceChapterDetached() {
        guard isSpeaking, let baseCtx = context, storage.acceptsBookWrite(baseCtx.writeToken) else { stop(); return }
        let nextIdx = baseCtx.chapterIndex + 1
        guard nextIdx < baseCtx.chapters.count else { stop(); return }
        let chapter = baseCtx.chapters[nextIdx]
        let book = baseCtx.book
        
        isLoadingAudio = true
        detachedAdvanceTask?.cancel()
        let token = workToken()
        detachedAdvanceTask = Task { [weak self] in
            guard let self = self else { return }
            let storage = self.storage
            var text: String? = storage.getCachedChapter(bookId: book.id, chapterIndex: chapter.index, chapterURL: chapter.url, sourceURL: book.sourceUrl)
            if text == nil {
                let source = await MainActor.run {
                    storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
                        ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
                }
                let nextURL = nextIdx + 1 < baseCtx.chapters.count ? baseCtx.chapters[nextIdx + 1].url : nil
                if let content = try? await self.chapterLoader(chapter, source, book.bookUrl, nextURL),
                   !Task.isCancelled {
                    let accepted = await MainActor.run {
                        guard self.accepts(token), self.isSpeaking else { return false }
                        _ = storage.saveChapterCache(bookId: book.id, chapterIndex: chapter.index,
                                                     content: content, writeToken: baseCtx.writeToken)
                        return self.accepts(token)
                    }
                    if accepted { text = content.text }
                }
            }
            guard !Task.isCancelled else { return }
            let loadedText = text
            await MainActor.run {
                guard self.accepts(token), self.isSpeaking else { return }
                self.isLoadingAudio = false
                // A reader page may have re-attached while we were loading — let it take over
                if let callback = self.onChapterFinished {
                    callback()
                    return
                }
                guard self.isSpeaking, let content = loadedText else {
                    self.stop()
                    return
                }
                let paras = ChapterTextFormatter.paragraphs(from: content, config: storage.readerConfig)
                guard !paras.isEmpty else { self.stop(); return }
                var newCtx = baseCtx
                newCtx.chapterIndex = nextIdx
                self.context = newCtx
                self.saveDetachedProgress(paragraphIndex: 0)
                self.startReading(paragraphs: paras, fromIndex: 0, bookTitle: book.title,
                                  chapterTitle: chapter.title, initiallyPaused: self.isPaused)
            }
        }
    }
    
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerToken: WorkToken?
    private var activeUtterance: AVSpeechUtterance?
    private var utteranceToken: WorkToken?
    /// Continuous silent audio keep-alive player that prevents iOS from suspending the app
    /// between paragraphs or during async online neural TTS / chapter network fetches when screen is locked
    private var keepAlivePlayer: AVAudioPlayer?
    private var speakingTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedAudio: [Int: Data] = [:]
    
    #if canImport(UIKit)
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    #endif
    
    private var paragraphs: [String] = []
    private var sleepTimer: Timer?
    private var isStoppingManually = false
    
    private override convenience init() {
        self.init(testing: false)
    }

    /// Tests use an isolated store and inert audio transport while exercising real notifications,
    /// queued paragraph callbacks and detached chapter loading.
    init(testing: Bool, storage: StorageManager = .shared, chapterLoader: ChapterLoader? = nil) {
        self.storage = storage
        usesSystemAudio = !testing
        self.chapterLoader = chapterLoader ?? { chapter, source, referer, nextURL in
            try await ChapterContentLoader.shared.load(chapter: chapter, source: source,
                                                      referer: referer, nextChapterURL: nextURL)
        }
        super.init()
        synthesizer.delegate = self
        if !testing {
            setupRemoteTransportControls()
            setupSystemNotifications()
        }
    }
    
    // MARK: - Audio Session & Background Keep-Alive Engine
    private func configureAudioSession() {
        guard usesSystemAudio else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true, options: [])
        } catch {
            try? session.setCategory(.playback)
            try? session.setActive(true)
        }
        #endif
    }
    
    private func startKeepAliveAudio() {
        guard usesSystemAudio else { return }
        configureAudioSession()
        if let kp = keepAlivePlayer {
            if !kp.isPlaying {
                kp.play()
            }
            return
        }
        let wavData = Self.makeSilentWavData(durationSeconds: 2, sampleRate: 8000)
        if let player = try? AVAudioPlayer(data: wavData) {
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            self.keepAlivePlayer = player
        }
    }
    
    private func stopKeepAliveAudio() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
    }
    
    private func renewBackgroundTaskAssertion() {
        guard usesSystemAudio else { return }
        #if canImport(UIKit)
        let app = UIApplication.shared
        let oldId = backgroundTaskId
        backgroundTaskId = app.beginBackgroundTask(withName: "LegadoReaderTTSKeepAlive") { [weak self] in
            guard let self = self else { return }
            if self.backgroundTaskId != .invalid {
                app.endBackgroundTask(self.backgroundTaskId)
                self.backgroundTaskId = .invalid
            }
        }
        if oldId != .invalid {
            app.endBackgroundTask(oldId)
        }
        #endif
    }
    
    private func endBackgroundTaskAssertion() {
        guard usesSystemAudio else { return }
        #if canImport(UIKit)
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
        #endif
    }
    
    // MARK: - Lock Screen & Control Center Media Player (MPNowPlayingInfoCenter)
    private func setupRemoteTransportControls() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isSpeaking && self.isPaused {
                self.togglePlayPause(paragraphs: self.paragraphs, currentIndex: self.currentParagraphIndex)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            return self.pauseByUser() ? .success : .commandFailed
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            return self.resumeOrPause() ? .success : .commandFailed
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isSpeaking else { return .commandFailed }
            self.skipNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isSpeaking else { return .commandFailed }
            self.skipPrevious()
            return .success
        }
        #endif
    }
    
    private func setupSystemNotifications() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        #endif
    }
    
    @objc func handleAudioInterruption(_ notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            interruptionPolicy.began(wasPlaying: isSpeaking && !isPaused,
                                     session: sessionStopCount, playback: playbackID)
            if isSpeaking && !isPaused {
                isPaused = true
                audioPlayer?.pause()
                if synthesizer.isSpeaking {
                    synthesizer.pauseSpeaking(at: .word)
                }
                stopKeepAliveAudio()
                endBackgroundTaskAssertion()
                updateNowPlayingInfo()
            }
        case .ended:
            let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            if interruptionPolicy.consume(systemAllowsResume: options.contains(.shouldResume),
                session: sessionStopCount, playback: playbackID, isSpeaking: isSpeaking, isPaused: isPaused) {
                isPaused = false
                guard usesSystemAudio else { return }
                configureAudioSession()
                startKeepAliveAudio()
                renewBackgroundTaskAssertion()
                if let player = audioPlayer {
                    player.play()
                } else if synthesizer.isPaused {
                    synthesizer.continueSpeaking()
                } else {
                    speakParagraph(at: currentParagraphIndex)
                }
                updateNowPlayingInfo()
            }
        @unknown default:
            break
        }
        #endif
    }
    
    @objc private func handleDidEnterBackground(_ notification: Notification) {
        if isSpeaking && !isPaused {
            configureAudioSession()
            startKeepAliveAudio()
            renewBackgroundTaskAssertion()
            updateNowPlayingInfo()
        }
    }
    
    public func updateNowPlayingMetadata(bookTitle: String, chapterTitle: String) {
        self.currentBookTitle = bookTitle
        self.currentChapterTitle = chapterTitle
        if isSpeaking {
            updateNowPlayingInfo()
        }
    }
    
    private func updateNowPlayingInfo() {
        guard usesSystemAudio else { return }
        #if os(iOS)
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentChapterTitle.isEmpty ? currentBookTitle : currentChapterTitle
        info[MPMediaItemPropertyArtist] = "\(currentBookTitle) · \(selectedVoice.shortName)"
        let total = max(1, paragraphs.count)
        let current = min(currentParagraphIndex + 1, total)
        info[MPMediaItemPropertyAlbumTitle] = "第 \(current)/\(total) 段"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentParagraphIndex)
        info[MPMediaItemPropertyPlaybackDuration] = Double(total)
        info[MPNowPlayingInfoPropertyPlaybackRate] = (isSpeaking && !isPaused) ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }
    
    // MARK: - Playback Controls
    public func startReading(paragraphs: [String], fromIndex: Int = 0, bookTitle: String? = nil,
                             chapterTitle: String? = nil, initiallyPaused: Bool = false) {
        guard !paragraphs.isEmpty else { return }
        if let context, !storage.acceptsBookWrite(context.writeToken) { stop(); return }
        if let bt = bookTitle, !bt.isEmpty { self.currentBookTitle = bt }
        if let ct = chapterTitle, !ct.isEmpty { self.currentChapterTitle = ct }
        
        configureAudioSession()
        startKeepAliveAudio()
        renewBackgroundTaskAssertion()
        
        stopCurrentPlaybackOnly()
        
        self.paragraphs = paragraphs
        self.prefetchedAudio.removeAll()
        let safeIndex = max(0, min(fromIndex, paragraphs.count - 1))
        self.currentParagraphIndex = safeIndex
        self.isSpeaking = true
        self.isPaused = initiallyPaused
        
        updateNowPlayingInfo()
        if initiallyPaused {
            stopKeepAliveAudio()
            endBackgroundTaskAssertion()
            return
        }
        speakParagraph(at: safeIndex)
    }
    
    public func togglePlayPause(paragraphs: [String], currentIndex: Int) {
        interruptionPolicy.cancel()
        if isSpeaking {
            if isPaused {
                isPaused = false
                guard usesSystemAudio else { return }
                configureAudioSession()
                startKeepAliveAudio()
                renewBackgroundTaskAssertion()
                if let player = audioPlayer {
                    player.play()
                } else if synthesizer.isPaused {
                    synthesizer.continueSpeaking()
                } else {
                    speakParagraph(at: currentParagraphIndex)
                }
                updateNowPlayingInfo()
            } else {
                isPaused = true
                if let player = audioPlayer, player.isPlaying {
                    player.pause()
                }
                if synthesizer.isSpeaking {
                    synthesizer.pauseSpeaking(at: .word)
                }
                stopKeepAliveAudio()
                endBackgroundTaskAssertion()
                updateNowPlayingInfo()
            }
        } else {
            startReading(paragraphs: paragraphs, fromIndex: currentIndex)
        }
    }

    /// A remote pause received while an interruption already paused audio still expresses
    /// a user intent, and must cancel the system's later automatic-resume permission.
    @discardableResult
    public func pauseByUser() -> Bool {
        interruptionPolicy.cancel()
        guard isSpeaking else { return false }
        isPaused = true
        audioPlayer?.pause()
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
        stopKeepAliveAudio()
        endBackgroundTaskAssertion()
        updateNowPlayingInfo()
        return true
    }
    
    public func stop() {
        sessionStopCount += 1
        detachedAdvanceTask?.cancel()
        detachedAdvanceTask = nil
        stopCurrentPlaybackOnly()
        stopKeepAliveAudio()
        endBackgroundTaskAssertion()
        isSpeaking = false
        isPaused = false
        isLoadingAudio = false
        paragraphs.removeAll()
        prefetchedAudio.removeAll()
        cancelSleepTimer()
        #if os(iOS)
        if usesSystemAudio { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        #endif
    }
    
    /// Stops the current chapter's audio for a chapter switch while keeping the listening
    /// session alive: the sleep timer, reading context and play/pause intent survive so the
    /// next chapter can resume. Unlike `stop()` this must never cancel the sleep timer.
    public func suspendForChapterTransition() {
        detachedAdvanceTask?.cancel()
        detachedAdvanceTask = nil
        stopCurrentPlaybackOnly()
        stopKeepAliveAudio()
        endBackgroundTaskAssertion()
        isSpeaking = false
        isPaused = false
        isLoadingAudio = false
        prefetchedAudio.removeAll()
        #if os(iOS)
        updateNowPlayingInfo()
        #endif
    }
    
    private func stopCurrentPlaybackOnly() {
        playbackID = UUID()
        paragraphWorkID = UUID()
        interruptionPolicy.cancel()
        activeUtterance = nil
        utteranceToken = nil
        audioPlayerToken = nil
        isStoppingManually = true
        speakingTask?.cancel()
        speakingTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
        }
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isStoppingManually = false
    }
    
    public func skipPrevious() {
        interruptionPolicy.cancel()
        guard isSpeaking, !paragraphs.isEmpty else { return }
        let prev = max(0, currentParagraphIndex - 1)
        startReading(paragraphs: paragraphs, fromIndex: prev)
    }
    
    public func skipNext() {
        interruptionPolicy.cancel()
        guard isSpeaking, !paragraphs.isEmpty else { return }
        if currentParagraphIndex + 1 < paragraphs.count {
            startReading(paragraphs: paragraphs, fromIndex: currentParagraphIndex + 1)
        } else {
            renewBackgroundTaskAssertion()
            handleChapterFinished()
        }
    }
    
    public func setRate(_ multiplier: Float) {
        speechRateMultiplier = multiplier
        prefetchedAudio.removeAll()
        if isSpeaking && !isPaused {
            startReading(paragraphs: paragraphs, fromIndex: currentParagraphIndex)
        }
    }
    
    public func setVoice(_ voice: NeuralVoiceActor) {
        selectedVoice = voice
        prefetchedAudio.removeAll()
        if isSpeaking && !isPaused {
            startReading(paragraphs: paragraphs, fromIndex: currentParagraphIndex)
        }
    }
    
    public func setSleepTimer(minutes: Int?) {
        cancelSleepTimer()
        sleepTimerMinutes = minutes
        guard let mins = minutes, mins > 0 else { return }
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let rem = self.sleepTimerMinutes {
                    if rem <= 1 {
                        self.stop()
                    } else {
                        self.sleepTimerMinutes = rem - 1
                    }
                }
            }
        }
    }
    
    private func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutes = nil
    }
    
    private func speakParagraph(at index: Int) {
        guard isSpeaking else { return }
        paragraphWorkID = UUID()
        let token = workToken()
        guard accepts(token) else { return }
        renewBackgroundTaskAssertion()
        startKeepAliveAudio()
        
        guard index >= 0 && index < paragraphs.count else {
            DispatchQueue.main.async {
                guard self.accepts(token), self.isSpeaking else { return }
                self.isLoadingAudio = false
                self.handleChapterFinished(token: token)
            }
            return
        }
        
        let rawText = paragraphs[index]
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if rawText.isEmpty {
            speakParagraph(at: index + 1)
            return
        }
        
        DispatchQueue.main.async {
            guard self.accepts(token), self.isSpeaking else { return }
            self.currentParagraphIndex = index
            self.updateNowPlayingInfo()
            if let callback = self.onParagraphChanged {
                callback(index)
            } else {
                self.saveDetachedProgress(paragraphIndex: index)
            }
        }
        guard usesSystemAudio else { return }
        
        let voice = selectedVoice
        let rate = speechRateMultiplier
        
        speakingTask?.cancel()
        speakingTask = Task {
            // 1. Check if already pre-synthesized in cache
            var mp3Data: Data? = await MainActor.run {
                guard self.accepts(token), !Task.isCancelled else { return nil }
                return self.prefetchedAudio.removeValue(forKey: index)
            }
            
            if mp3Data == nil {
                let mayStart = await MainActor.run {
                    guard self.accepts(token), self.isSpeaking, !Task.isCancelled else { return false }
                    self.isLoadingAudio = true
                    return true
                }
                guard mayStart else { return }
                mp3Data = try? await EdgeNeuralTTS.shared.synthesize(text: rawText, voice: voice, rateMultiplier: rate)
                await MainActor.run {
                    guard self.accepts(token), !Task.isCancelled else { return }
                    self.isLoadingAudio = false
                }
            }
            
            guard !Task.isCancelled else { return }
            
            // Start prefetching the NEXT 2 paragraphs in the background while current paragraph plays!
            let mayContinue = await MainActor.run {
                guard self.accepts(token), self.isSpeaking else { return false }
                self.triggerPrefetchQueue(startingAfter: index, voice: voice, rate: rate)
                return true
            }
            guard mayContinue else { return }
            
            if let data = mp3Data, data.count > 256 {
                await MainActor.run {
                    guard self.accepts(token), self.isSpeaking, !self.isPaused, !Task.isCancelled else { return }
                    self.configureAudioSession()
                    self.startKeepAliveAudio()
                    do {
                        let player = try AVAudioPlayer(data: data)
                        player.delegate = self
                        player.prepareToPlay()
                        self.audioPlayer = player
                        self.audioPlayerToken = token
                        if !player.play() {
                            self.speakWithLocalEnhancedVoice(rawText, rate: rate)
                        }
                    } catch {
                        self.speakWithLocalEnhancedVoice(rawText, rate: rate)
                    }
                }
            } else {
                // Offline fallback: use highest-quality local iOS Enhanced/Premium Siri voice
                await MainActor.run {
                    guard self.accepts(token), self.isSpeaking, !self.isPaused, !Task.isCancelled else { return }
                    self.configureAudioSession()
                    self.startKeepAliveAudio()
                    self.speakWithLocalEnhancedVoice(rawText, rate: rate)
                }
            }
        }
    }
    
    private func triggerPrefetchQueue(startingAfter index: Int, voice: NeuralVoiceActor, rate: Float) {
        let token = workToken()
        let candidates = [index + 1, index + 2].filter { $0 >= 0 && $0 < paragraphs.count }
        guard !candidates.isEmpty else { return }
        
        prefetchTask?.cancel()
        prefetchTask = Task {
            for nextIndex in candidates {
                guard !Task.isCancelled else { return }
                let mayContinue = await MainActor.run { self.accepts(token) && self.isSpeaking }
                guard mayContinue else { return }
                let alreadyCached = await MainActor.run { self.prefetchedAudio[nextIndex] != nil }
                if alreadyCached { continue }
                
                let nextText: String = await MainActor.run {
                    guard self.accepts(token), self.isSpeaking, !Task.isCancelled,
                          nextIndex < self.paragraphs.count else { return "" }
                    return self.paragraphs[nextIndex]
                        .replacingOccurrences(of: "　", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard !nextText.isEmpty else { continue }
                
                if let data = try? await EdgeNeuralTTS.shared.synthesize(text: nextText, voice: voice, rateMultiplier: rate),
                   !Task.isCancelled {
                    await MainActor.run {
                        guard self.accepts(token), self.isSpeaking, !Task.isCancelled else { return }
                        self.prefetchedAudio[nextIndex] = data
                    }
                }
            }
        }
    }
    
    private func speakWithLocalEnhancedVoice(_ text: String, rate: Float) {
        // A failed online player must not later finish over the local fallback's utterance.
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerToken = nil
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.selectBestLocalChineseVoice()
        let baseRate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, baseRate * rate))
        utterance.pitchMultiplier = 1.03
        utterance.postUtteranceDelay = 0.12
        activeUtterance = utterance
        utteranceToken = workToken()
        synthesizer.speak(utterance)
    }
    
    private static func selectBestLocalChineseVoice() -> AVSpeechSynthesisVoice? {
        let zhVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "zh-CN" || $0.language.hasPrefix("zh-Hans")
        }
        if let best = zhVoices.sorted(by: { $0.quality.rawValue > $1.quality.rawValue }).first {
            return best
        }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }
    
    // MARK: - AVAudioPlayerDelegate (Online Neural Audio Finished)
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        guard let token = audioPlayerToken, accepts(token) else { return }
        guard !isStoppingManually, isSpeaking, !isPaused else { return }
        advanceToNextParagraphOrChapter()
    }
    
    // MARK: - AVSpeechSynthesizerDelegate (Offline Fallback Finished)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance, let token = utteranceToken, accepts(token) else { return }
        guard !isStoppingManually, isSpeaking, !isPaused else { return }
        advanceToNextParagraphOrChapter()
    }
    
    private func advanceToNextParagraphOrChapter() {
        let token = workToken()
        guard accepts(token), isSpeaking else { return }
        renewBackgroundTaskAssertion()
        startKeepAliveAudio()
        let nextIndex = currentParagraphIndex + 1
        if nextIndex < paragraphs.count {
            speakParagraph(at: nextIndex)
        } else {
            DispatchQueue.main.async {
                self.handleChapterFinished(token: token)
            }
        }
    }
    
    // MARK: - In-Memory Silent WAV Generator (Guarantees Non-Stop Background Audio Session)
    private static func makeSilentWavData(durationSeconds: Int = 2, sampleRate: Int = 8000) -> Data {
        let numSamples = durationSeconds * sampleRate
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataSize = UInt32(numSamples * Int(blockAlign))
        let chunkSize = 36 + dataSize
        
        var data = Data()
        data.reserveCapacity(Int(44 + dataSize))
        
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var cs = chunkSize.littleEndian
        withUnsafeBytes(of: &cs) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size = UInt32(16).littleEndian
        withUnsafeBytes(of: &subchunk1Size) { data.append(contentsOf: $0) }
        var audioFormat = UInt16(1).littleEndian // PCM = 1
        withUnsafeBytes(of: &audioFormat) { data.append(contentsOf: $0) }
        var channels = numChannels.littleEndian
        withUnsafeBytes(of: &channels) { data.append(contentsOf: $0) }
        var sr = UInt32(sampleRate).littleEndian
        withUnsafeBytes(of: &sr) { data.append(contentsOf: $0) }
        var br = byteRate.littleEndian
        withUnsafeBytes(of: &br) { data.append(contentsOf: $0) }
        var ba = blockAlign.littleEndian
        withUnsafeBytes(of: &ba) { data.append(contentsOf: $0) }
        var bps = bitsPerSample.littleEndian
        withUnsafeBytes(of: &bps) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var ds = dataSize.littleEndian
        withUnsafeBytes(of: &ds) { data.append(contentsOf: $0) }
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
