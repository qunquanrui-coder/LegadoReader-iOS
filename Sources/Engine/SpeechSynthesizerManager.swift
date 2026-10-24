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
    }
    @Published public private(set) var context: ReadingContext?
    private var detachedAdvanceTask: Task<Void, Never>?
    
    public func setContext(book: Book, chapters: [Chapter], chapterIndex: Int) {
        guard !chapters.isEmpty else { return }
        context = ReadingContext(book: book, chapters: chapters, chapterIndex: chapterIndex)
    }
    
    /// Called by the reader page when it is closed: callbacks referencing the closed page are dropped,
    /// and the engine continues on its own using `context`.
    public func detachReader() {
        onParagraphChanged = nil
        onChapterFinished = nil
    }
    
    /// Play / pause without needing the paragraph list (used by bookshelf mini player & lock screen)
    public func resumeOrPause() {
        guard isSpeaking, !paragraphs.isEmpty else { return }
        togglePlayPause(paragraphs: paragraphs, currentIndex: currentParagraphIndex)
    }
    
    private func handleChapterFinished() {
        renewBackgroundTaskAssertion()
        startKeepAliveAudio()
        if let callback = onChapterFinished {
            callback()
        } else {
            advanceChapterDetached()
        }
    }
    
    private func saveDetachedProgress(paragraphIndex: Int) {
        guard let ctx = context, ctx.chapterIndex < ctx.chapters.count else { return }
        StorageManager.shared.updateBookProgress(
            bookId: ctx.book.id,
            bookTitle: ctx.book.title,
            bookAuthor: ctx.book.author,
            chapterIndex: ctx.chapterIndex,
            chapterTitle: ctx.chapters[ctx.chapterIndex].title,
            totalChapters: ctx.chapters.count,
            paragraphIndex: paragraphIndex
        )
    }
    
    /// Loads the next chapter (cache first, then network) and continues reading — no reader page required
    private func advanceChapterDetached() {
        guard let baseCtx = context else { stop(); return }
        let nextIdx = baseCtx.chapterIndex + 1
        guard nextIdx < baseCtx.chapters.count else { stop(); return }
        let chapter = baseCtx.chapters[nextIdx]
        let book = baseCtx.book
        
        isLoadingAudio = true
        detachedAdvanceTask?.cancel()
        detachedAdvanceTask = Task { [weak self] in
            guard let self = self else { return }
            let storage = StorageManager.shared
            var text: String? = storage.getCachedChapter(bookId: book.id, chapterIndex: chapter.index, chapterURL: chapter.url, sourceURL: book.sourceUrl)
            if text == nil {
                let source = await MainActor.run {
                    storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
                        ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
                }
                let nextURL = nextIdx + 1 < baseCtx.chapters.count ? baseCtx.chapters[nextIdx + 1].url : nil
                if let content = try? await ChapterContentLoader.shared.load(chapter: chapter, source: source,
                                                                           referer: book.bookUrl, nextChapterURL: nextURL),
                   !Task.isCancelled {
                    storage.saveChapterCache(bookId: book.id, chapterIndex: chapter.index, content: content)
                    text = content.text
                }
            }
            guard !Task.isCancelled else { return }
            let loadedText = text
            await MainActor.run {
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
    
    private override init() {
        super.init()
        synthesizer.delegate = self
        setupRemoteTransportControls()
        setupSystemNotifications()
    }
    
    // MARK: - Audio Session & Background Keep-Alive Engine
    private func configureAudioSession() {
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
            if self.isSpeaking && !self.isPaused {
                self.togglePlayPause(paragraphs: self.paragraphs, currentIndex: self.currentParagraphIndex)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self, !self.paragraphs.isEmpty else { return .commandFailed }
            self.togglePlayPause(paragraphs: self.paragraphs, currentIndex: self.currentParagraphIndex)
            return .success
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
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        #if os(iOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            if isSpeaking && !isPaused {
                isPaused = true
                audioPlayer?.pause()
                if synthesizer.isSpeaking {
                    synthesizer.pauseSpeaking(at: .word)
                }
                updateNowPlayingInfo()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume), isSpeaking, isPaused {
                isPaused = false
                configureAudioSession()
                startKeepAliveAudio()
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
        if isSpeaking {
            if isPaused {
                isPaused = false
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
    
    public func stop() {
        detachedAdvanceTask?.cancel()
        detachedAdvanceTask = nil
        stopCurrentPlaybackOnly()
        stopKeepAliveAudio()
        endBackgroundTaskAssertion()
        isSpeaking = false
        isPaused = false
        isLoadingAudio = false
        prefetchedAudio.removeAll()
        cancelSleepTimer()
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }
    
    private func stopCurrentPlaybackOnly() {
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
        guard isSpeaking, !paragraphs.isEmpty else { return }
        let prev = max(0, currentParagraphIndex - 1)
        startReading(paragraphs: paragraphs, fromIndex: prev)
    }
    
    public func skipNext() {
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
        renewBackgroundTaskAssertion()
        startKeepAliveAudio()
        
        guard index >= 0 && index < paragraphs.count else {
            DispatchQueue.main.async {
                self.isLoadingAudio = false
                self.handleChapterFinished()
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
            self.currentParagraphIndex = index
            self.updateNowPlayingInfo()
            if let callback = self.onParagraphChanged {
                callback(index)
            } else {
                self.saveDetachedProgress(paragraphIndex: index)
            }
        }
        
        let voice = selectedVoice
        let rate = speechRateMultiplier
        
        speakingTask?.cancel()
        speakingTask = Task {
            // 1. Check if already pre-synthesized in cache
            var mp3Data: Data? = await MainActor.run { self.prefetchedAudio.removeValue(forKey: index) }
            
            if mp3Data == nil {
                await MainActor.run { self.isLoadingAudio = true }
                mp3Data = try? await EdgeNeuralTTS.shared.synthesize(text: rawText, voice: voice, rateMultiplier: rate)
                await MainActor.run { self.isLoadingAudio = false }
            }
            
            guard !Task.isCancelled else { return }
            
            // Start prefetching the NEXT 2 paragraphs in the background while current paragraph plays!
            self.triggerPrefetchQueue(startingAfter: index, voice: voice, rate: rate)
            
            if let data = mp3Data, data.count > 256 {
                await MainActor.run {
                    guard self.isSpeaking, !self.isPaused else { return }
                    self.configureAudioSession()
                    self.startKeepAliveAudio()
                    do {
                        let player = try AVAudioPlayer(data: data)
                        player.delegate = self
                        player.prepareToPlay()
                        self.audioPlayer = player
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
                    guard self.isSpeaking, !self.isPaused else { return }
                    self.configureAudioSession()
                    self.startKeepAliveAudio()
                    self.speakWithLocalEnhancedVoice(rawText, rate: rate)
                }
            }
        }
    }
    
    private func triggerPrefetchQueue(startingAfter index: Int, voice: NeuralVoiceActor, rate: Float) {
        let candidates = [index + 1, index + 2].filter { $0 >= 0 && $0 < paragraphs.count }
        guard !candidates.isEmpty else { return }
        
        prefetchTask?.cancel()
        prefetchTask = Task {
            for nextIndex in candidates {
                guard !Task.isCancelled else { return }
                let alreadyCached = await MainActor.run { self.prefetchedAudio[nextIndex] != nil }
                if alreadyCached { continue }
                
                let nextText: String = await MainActor.run {
                    guard nextIndex < self.paragraphs.count else { return "" }
                    return self.paragraphs[nextIndex]
                        .replacingOccurrences(of: "　", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard !nextText.isEmpty else { continue }
                
                if let data = try? await EdgeNeuralTTS.shared.synthesize(text: nextText, voice: voice, rateMultiplier: rate),
                   !Task.isCancelled {
                    await MainActor.run {
                        self.prefetchedAudio[nextIndex] = data
                    }
                }
            }
        }
    }
    
    private func speakWithLocalEnhancedVoice(_ text: String, rate: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.selectBestLocalChineseVoice()
        let baseRate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, baseRate * rate))
        utterance.pitchMultiplier = 1.03
        utterance.postUtteranceDelay = 0.12
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
        guard !isStoppingManually, isSpeaking, !isPaused else { return }
        advanceToNextParagraphOrChapter()
    }
    
    // MARK: - AVSpeechSynthesizerDelegate (Offline Fallback Finished)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !isStoppingManually, isSpeaking, !isPaused else { return }
        advanceToNextParagraphOrChapter()
    }
    
    private func advanceToNextParagraphOrChapter() {
        renewBackgroundTaskAssertion()
        startKeepAliveAudio()
        let nextIndex = currentParagraphIndex + 1
        if nextIndex < paragraphs.count {
            speakParagraph(at: nextIndex)
        } else {
            DispatchQueue.main.async {
                self.handleChapterFinished()
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
