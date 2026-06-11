//
//  SpeechAnnouncer.swift
//  PushBro
//

import AVFoundation
import Foundation

@MainActor
protocol Announcing: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String)
}

/// AVSpeechSynthesizer wrapper. `isSpeaking` gates the voice-command listener
/// so TTS output can't trigger commands through the nearby mic.
@Observable
final class SpeechAnnouncer: NSObject, Announcing {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    /// Extra gate time after an utterance ends, to cover speaker/mic echo tail.
    private(set) var lastFinishedAt: Date = .distantPast

    var isEnabled = true

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String) {
        guard isEnabled else { return }
        Log.audio.debug("Speaking: \"\(text)\"")
        // Drop anything still queued so fast rep counts never lag behind reality.
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = false
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.lastFinishedAt = .now
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.lastFinishedAt = .now
        }
    }
}
