//
//  AudioSessionCoordinator.swift
//  PushBro
//

import AVFoundation
import Foundation

/// Single owner of the shared AVAudioSession so TTS, speech recognition, and
/// ARKit don't fight over it. Activation order matters: start the ARSession
/// first, then this, then any AVAudioEngine.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    /// Called with `true` when an interruption (call, Siri) begins and
    /// `false` when it ends.
    var onInterruption: ((Bool) -> Void)?

    private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            MainActor.assumeIsolated {
                if type == .began {
                    Log.audio.warning("Audio session interrupted (call/Siri)")
                } else {
                    Log.audio.info("Audio session interruption ended")
                }
                self?.onInterruption?(type == .began)
            }
        }
    }

    /// `recording: true` when voice commands need the mic. Without it a
    /// playback-only category avoids the mic permission entirely.
    /// `.defaultToSpeaker` is mandatory — otherwise TTS routes to the
    /// earpiece and is inaudible from plank position.
    func activate(recording: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if recording {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            } else {
                try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            }
            try session.setActive(true)
            Log.audio.info("Audio session active (\(recording ? "playAndRecord + speaker" : "playback"))")
        } catch {
            // Audio is a convenience, not a requirement — counting still works.
            Log.audio.error("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    func deactivate() {
        Log.audio.debug("Audio session deactivated")
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
