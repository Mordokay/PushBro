//
//  CalibrationController.swift
//  PushBro
//

import Foundation

/// Drives the calibration wizard: consumes the distance stream, averages
/// capture windows, and runs a practice state machine for the test step.
@Observable
final class CalibrationController {
    enum Step: Equatable {
        case intro
        case capturingUp
        case betweenCaptures
        case capturingDown
        case test
    }

    enum Position: String {
        case up
        case down
    }

    private(set) var step: Step = .intro
    private(set) var isTracking = false
    /// 3, 2, 1 before the measuring window; nil while measuring.
    private(set) var captureCountdown: Int?
    private(set) var currentDepth: Double?
    private(set) var testRepCount = 0
    private(set) var failedRangeCheck = false
    /// Set when a measuring window ends with no usable samples (face was
    /// never tracked) so the view can tell the user what went wrong.
    private(set) var failedCapture: Position?
    private(set) var profile: CalibrationProfile?

    private let provider: any FaceDistanceProviding
    private var consumeTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    private var latestDistance: Double?
    private var smoother = DistanceSmoother()
    private var collecting = false
    private var collected: [Double] = []
    /// Untracked frames seen while the measuring window was open.
    private var collectedNils = 0
    private var capturedUp: Double?
    private var testMachine: RepCounterStateMachine?

    init(provider: any FaceDistanceProviding) {
        self.provider = provider
    }

    func activate() {
        guard consumeTask == nil else { return }
        Log.calibration.info("Session starting (provider: \(type(of: provider)))")
        provider.start()
        consumeTask = Task { [weak self] in
            guard let stream = self?.provider.samples else { return }
            for await sample in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(sample)
            }
        }
    }

    func deactivate() {
        Log.calibration.debug("Session deactivated")
        consumeTask?.cancel()
        consumeTask = nil
        captureTask?.cancel()
        captureTask = nil
        provider.stop()
    }

    func restart() {
        Log.calibration.info("Wizard restarted")
        captureTask?.cancel()
        captureTask = nil
        step = .intro
        captureCountdown = nil
        capturedUp = nil
        profile = nil
        testMachine = nil
        testRepCount = 0
        failedRangeCheck = false
        failedCapture = nil
        collecting = false
        collected = []
        collectedNils = 0
    }

    /// Up: hold still, 1 s average. Down: tracking dies below the sensor's
    /// envelope before the real bottom, so the user *descends during* a longer
    /// window and we keep the lowest reliable distance seen.
    func beginCapture(_ position: Position) {
        Log.calibration.info("Capturing \(position.rawValue) position — countdown started")
        step = position == .up ? .capturingUp : .capturingDown
        failedRangeCheck = false
        failedCapture = nil
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            for remaining in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                captureCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            captureCountdown = nil
            collected = []
            collectedNils = 0
            collecting = true
            Log.calibration.debug("Measuring window open for \(position.rawValue) (tracking: \(isTracking), last distance: \(latestDistance.map { String(format: "%.3f m", $0) } ?? "none"))")
            try? await Task.sleep(for: .seconds(position == .up ? 1.0 : 4.0))
            guard !Task.isCancelled else { return }
            collecting = false
            finishCapture(position)
        }
    }

    private func finishCapture(_ position: Position) {
        guard !collected.isEmpty else {
            Log.calibration.error("\(position.rawValue) capture failed: 0 tracked samples in the window (\(collectedNils) untracked frames). Face likely below sensor minimum range or out of frame.")
            failedCapture = position
            step = position == .up ? .intro : .betweenCaptures
            return
        }
        let average = collected.reduce(0, +) / Double(collected.count)
        let minimum = collected.min() ?? average
        let maximum = collected.max() ?? average
        Log.calibration.info(String(
            format: "%@ captured: avg %.3f m (min %.3f, max %.3f, %d samples, %d untracked frames)",
            position.rawValue, average, minimum, maximum, collected.count, collectedNils
        ))

        switch position {
        case .up:
            if collectedNils > collected.count {
                Log.calibration.warning("up window was untracked more than half the time — value may be unreliable")
            }
            capturedUp = average
            step = .betweenCaptures
        case .down:
            guard let up = capturedUp else {
                Log.calibration.error("Down captured but up value is missing — restarting wizard")
                restart()
                return
            }
            // The face leaves the tracking envelope before the true bottom
            // (it exits the camera's view as the body drops), so the lowest
            // reliable distances seen during the descent stand in for it.
            let lowest = collected.sorted().prefix(max(5, collected.count / 10))
            let down = lowest.reduce(0, +) / Double(lowest.count)
            Log.calibration.info(String(format: "down position from lowest %d tracked samples: %.3f m", lowest.count, down))
            let candidate = CalibrationProfile(upDistance: up, downDistance: down, createdAt: .now)
            if candidate.isPlausible {
                Log.calibration.info(String(format: "Profile plausible: up %.3f m, down %.3f m, range %.1f cm", up, average, candidate.range * 100))
                profile = candidate
                startTest(with: candidate)
            } else {
                Log.calibration.error(String(format: "Range check failed: up %.3f m, down %.3f m, range %.1f cm (need ≥ %.0f cm)", up, average, candidate.range * 100, CalibrationProfile.minimumRange * 100))
                failedRangeCheck = true
            }
        }
    }

    private func startTest(with profile: CalibrationProfile) {
        let config = RepDetectionConfig(
            calibration: profile,
            downThreshold: AppSettings.defaultDownThreshold,
            restThreshold: AppSettings.defaultRestThreshold
        )
        Log.calibration.info("Test step started")
        testMachine = RepCounterStateMachine(config: config)
        testRepCount = 0
        smoother.reset()
        step = .test
    }

    private func handle(_ sample: DistanceSample) {
        let smoothed = smoother.smooth(sample.distance)
        latestDistance = smoothed
        let nowTracking = smoothed != nil
        if nowTracking != isTracking {
            if nowTracking {
                Log.calibration.debug(String(format: "Tracking acquired at %.3f m", smoothed ?? 0))
            } else {
                Log.calibration.debug("Tracking lost (step: \(step), collecting: \(collecting))")
            }
        }
        isTracking = nowTracking

        if collecting {
            if let smoothed {
                collected.append(smoothed)
            } else {
                collectedNils += 1
            }
        }

        if var machine = testMachine {
            let events = machine.process(DistanceSample(distance: smoothed, timestamp: sample.timestamp))
            testMachine = machine
            currentDepth = machine.currentDepth
            for event in events {
                switch event {
                case .repCompleted:
                    testRepCount += 1
                    Log.calibration.debug("Practice rep \(testRepCount) registered")
                case .partialRepRejected:
                    Log.calibration.debug("Practice rep rejected as partial")
                default:
                    break
                }
            }
        }
    }
}
