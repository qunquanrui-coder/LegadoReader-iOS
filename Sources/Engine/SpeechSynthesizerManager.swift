import Foundation
import AVFoundation
import Combine

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
    
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var speakingTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedAudio: [Int: Data] = [:]
    
    private var paragraphs: [String] = []
    private var sleepTimer: Timer?
    private var isStoppingManually = false
    
    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .duckOthers])
        try? session.setActive(true)
        #endif
    }
    
    public func startReading(paragraphs: [String], fromIndex: Int = 0) {
        guard !paragraphs.isEmpty else { return }
        configureAudioSession()
        
        stopCurrentPlaybackOnly()
        
        self.paragraphs = paragraphs
        self.prefetchedAudio.removeAll()
        let safeIndex = max(0, min(fromIndex, paragraphs.count - 1))
        self.currentParagraphIndex = safeIndex
        self.isSpeaking = true
        self.isPaused = false
        
        speakParagraph(at: safeIndex)
    }
    
    public func togglePlayPause(paragraphs: [String], currentIndex: Int) {
        if isSpeaking {
            if isPaused {
                isPaused = false
                if let player = audioPlayer {
                    player.play()
                } else if synthesizer.isPaused {
                    synthesizer.continueSpeaking()
                } else {
                    speakParagraph(at: currentParagraphIndex)
                }
            } else {
                isPaused = true
                if let player = audioPlayer, player.isPlaying {
                    player.pause()
                }
                if synthesizer.isSpeaking {
                    synthesizer.pauseSpeaking(at: .word)
                }
            }
        } else {
            startReading(paragraphs: paragraphs, fromIndex: currentIndex)
        }
    }
    
    public func stop() {
        stopCurrentPlaybackOnly()
        isSpeaking = false
        isPaused = false
        isLoadingAudio = false
        prefetchedAudio.removeAll()
        cancelSleepTimer()
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
            onChapterFinished?()
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
        guard index >= 0 && index < paragraphs.count else {
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.isPaused = false
                self.isLoadingAudio = false
                self.onChapterFinished?()
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
            self.onParagraphChanged?(index)
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
            
            // Start prefetching the NEXT paragraph in the background while current paragraph plays!
            self.triggerPrefetch(for: index + 1, voice: voice, rate: rate)
            
            if let data = mp3Data, data.count > 256 {
                await MainActor.run {
                    guard self.isSpeaking, !self.isPaused else { return }
                    do {
                        let player = try AVAudioPlayer(data: data)
                        player.delegate = self
                        player.prepareToPlay()
                        self.audioPlayer = player
                        player.play()
                    } catch {
                        self.speakWithLocalEnhancedVoice(rawText, rate: rate)
                    }
                }
            } else {
                // Offline fallback: use highest-quality local iOS Enhanced/Premium Siri voice
                await MainActor.run {
                    guard self.isSpeaking, !self.isPaused else { return }
                    self.speakWithLocalEnhancedVoice(rawText, rate: rate)
                }
            }
        }
    }
    
    private func triggerPrefetch(for nextIndex: Int, voice: NeuralVoiceActor, rate: Float) {
        guard nextIndex >= 0 && nextIndex < paragraphs.count else { return }
        let nextText = paragraphs[nextIndex]
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextText.isEmpty else { return }
        
        prefetchTask?.cancel()
        prefetchTask = Task {
            if let data = try? await EdgeNeuralTTS.shared.synthesize(text: nextText, voice: voice, rateMultiplier: rate),
               !Task.isCancelled {
                await MainActor.run {
                    self.prefetchedAudio[nextIndex] = data
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
        utterance.postUtteranceDelay = 0.15
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
        guard !isStoppingManually, isSpeaking, !isPaused else { return }
        advanceToNextParagraphOrChapter()
    }
    
    // MARK: - AVSpeechSynthesizerDelegate (Offline Fallback Finished)
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !isStoppingManually, isSpeaking, !isPaused else { return }
        advanceToNextParagraphOrChapter()
    }
    
    private func advanceToNextParagraphOrChapter() {
        let nextIndex = currentParagraphIndex + 1
        if nextIndex < paragraphs.count {
            speakParagraph(at: nextIndex)
        } else {
            DispatchQueue.main.async {
                self.onChapterFinished?()
            }
        }
    }
}
