import Foundation
import AVFoundation
import Combine

public final class SpeechSynthesizerManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = SpeechSynthesizerManager()
    
    @Published public var isSpeaking: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var currentParagraphIndex: Int = 0
    @Published public var speechRateMultiplier: Float = 1.0
    @Published public var sleepTimerMinutes: Int? = nil
    
    public var onParagraphChanged: ((Int) -> Void)?
    public var onChapterFinished: (() -> Void)?
    
    private let synthesizer = AVSpeechSynthesizer()
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
        
        isStoppingManually = true
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isStoppingManually = false
        
        self.paragraphs = paragraphs
        let safeIndex = max(0, min(fromIndex, paragraphs.count - 1))
        self.currentParagraphIndex = safeIndex
        self.isSpeaking = true
        self.isPaused = false
        
        speakParagraph(at: safeIndex)
    }
    
    public func togglePlayPause(paragraphs: [String], currentIndex: Int) {
        if isSpeaking {
            if isPaused {
                synthesizer.continueSpeaking()
                isPaused = false
            } else {
                synthesizer.pauseSpeaking(at: .word)
                isPaused = true
            }
        } else {
            startReading(paragraphs: paragraphs, fromIndex: currentIndex)
        }
    }
    
    public func stop() {
        isStoppingManually = true
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        cancelSleepTimer()
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
        
        let utterance = AVSpeechUtterance(string: rawText)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, baseRate * speechRateMultiplier))
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.18
        synthesizer.speak(utterance)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !isStoppingManually, isSpeaking else { return }
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
