//
//  VoiceCommandListener.swift
//  PushBro
//

import AVFoundation
import Foundation
import Speech

/// Continuous keyword spotting for "start" and "stop" via SFSpeechRecognizer.
/// Defends against self-triggering (the speaker and mic are centimeters
/// apart on the floor) by gating on the announcer's isSpeaking state, and
/// against silent recognizer death by restarting the task on a timer.
@Observable
final class VoiceCommandListener {
    enum Command {
        case start
        case stop
    }

    private(set) var isListening = false
    private(set) var isAuthorized = false

    var onCommand: ((Command) -> Void)?
    weak var announcer: SpeechAnnouncer?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTask: Task<Void, Never>?
    private var lastCommandAt = Date.distantPast
    /// Bumped on every new recognition task. Callbacks from older (cancelled)
    /// tasks are ignored — cancelling a task fires its handler with an error,
    /// which must not be mistaken for a recognizer failure.
    private var taskGeneration = 0
    /// Restarts since the last time actual speech was heard, for log
    /// rate-limiting and error backoff.
    private var consecutiveRestarts = 0

    /// Echo tail after TTS finishes during which matches are ignored.
    private let speechGateTail: TimeInterval = 0.3
    /// Ignore further matches for this long after acting on a command.
    private let commandDebounce: TimeInterval = 2.0
    /// Defensive restart interval; recognition tasks die silently with age.
    private let restartInterval: TimeInterval = 55

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            Log.voice.warning("Speech recognition not authorized (status: \(speechStatus.rawValue)) — voice commands disabled")
            isAuthorized = false
            return false
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        if !micGranted {
            Log.voice.warning("Microphone permission denied — voice commands disabled")
        }
        isAuthorized = micGranted
        return micGranted
    }

    func startListening() {
        guard !isListening, isAuthorized else { return }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            Log.voice.warning("Speech recognizer unavailable for en-US — voice commands disabled")
            return
        }

        do {
            try startAudioEngine()
        } catch {
            Log.voice.error("Audio engine failed to start: \(error.localizedDescription)")
            return
        }
        Log.voice.info("Listening for commands (on-device recognition: \(recognizer.supportsOnDeviceRecognition))")
        isListening = true
        consecutiveRestarts = 0
        startRecognitionTask()
        scheduleRestart()
    }

    func stopListening() {
        guard isListening else { return }
        Log.voice.info("Stopped listening")
        isListening = false
        restartTask?.cancel()
        restartTask = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Internals

    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        // Query the format only after any voice processing is configured —
        // it changes the tap format.
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "VoiceCommandListener", code: 1)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startRecognitionTask() {
        taskGeneration += 1
        let generation = taskGeneration
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = ["start", "stop"]
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, generation == self.taskGeneration else { return }
                if let result {
                    self.consecutiveRestarts = 0
                    self.handleTranscript(result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.startRecognitionTask()
                    }
                } else if let error {
                    self.handleTaskEnd(error, generation: generation)
                }
            }
        }
    }

    /// The recognizer routinely ends its task with "no speech detected" after
    /// a few silent seconds — continuous keyword spotting just starts a fresh
    /// one. Only unexpected errors are worth a warning, and repeated failures
    /// back off so a broken recognizer can't spin.
    private func handleTaskEnd(_ error: any Error, generation: Int) {
        consecutiveRestarts += 1

        let nsError = error as NSError
        let isRoutineSilence = nsError.localizedDescription.localizedCaseInsensitiveContains("no speech")
        let shouldLog = consecutiveRestarts == 1 || consecutiveRestarts % 20 == 0
        let delay: Duration

        if isRoutineSilence {
            if shouldLog {
                Log.voice.debug("Restarting after silence (\(consecutiveRestarts)x since last speech)")
            }
            delay = .milliseconds(300)
        } else {
            if shouldLog {
                Log.voice.warning("Recognition task failed (\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)) — restarting with backoff (\(consecutiveRestarts)x)")
            }
            // 0.6 s, 1.2 s, 2.4 s … capped at 10 s.
            let exponent = min(consecutiveRestarts, 5)
            delay = .milliseconds(min(10_000, 300 * (1 << exponent)))
        }

        restartAfter(delay, ifStillOn: generation)
    }

    private func restartAfter(_ delay: Duration, ifStillOn generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.isListening, generation == self.taskGeneration else { return }
            self.startRecognitionTask()
        }
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.restartInterval ?? 55))
                guard let self, !Task.isCancelled, self.isListening else { return }
                self.startRecognitionTask()
            }
        }
    }

    private func handleTranscript(_ transcript: String) {
        // Word-boundary match on the most recent token — "restart" must not
        // match "start".
        guard let lastWord = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .last(where: { !$0.isEmpty }) else { return }

        let command: Command? = switch lastWord {
        case "start": .start
        case "stop": .stop
        default: nil
        }
        guard let command else { return }

        // Hard gate: never act while (or right after) our own TTS is playing.
        if let announcer {
            if announcer.isSpeaking {
                Log.voice.debug("Suppressed \"\(lastWord)\" — TTS is speaking")
                return
            }
            if Date().timeIntervalSince(announcer.lastFinishedAt) < speechGateTail {
                Log.voice.debug("Suppressed \"\(lastWord)\" — within TTS echo tail")
                return
            }
        }
        guard Date().timeIntervalSince(lastCommandAt) > commandDebounce else {
            Log.voice.debug("Suppressed \"\(lastWord)\" — within command debounce")
            return
        }

        Log.voice.info("Command recognized: \"\(lastWord)\"")
        lastCommandAt = .now
        onCommand?(command)
        // A fresh task avoids the old transcript re-matching the same word.
        startRecognitionTask()
    }
}
