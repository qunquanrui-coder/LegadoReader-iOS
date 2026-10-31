import Foundation

/// System permission to resume is not a new user request to play. Keep eligibility tied to
/// the playback session that was actually playing when the interruption began.
struct SpeechInterruptionPolicy {
    private var candidate: (session: Int, playback: UUID)?

    mutating func began(wasPlaying: Bool, session: Int, playback: UUID) {
        candidate = wasPlaying ? (session, playback) : nil
    }

    mutating func cancel() { candidate = nil }

    mutating func consume(systemAllowsResume: Bool, session: Int, playback: UUID,
                          isSpeaking: Bool, isPaused: Bool) -> Bool {
        let saved = candidate
        candidate = nil
        return systemAllowsResume && isSpeaking && isPaused
            && saved?.session == session && saved?.playback == playback
    }
}
