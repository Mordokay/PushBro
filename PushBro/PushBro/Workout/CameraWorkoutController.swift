//
//  CameraWorkoutController.swift
//  PushBro
//

import Foundation

/// Wires the face-distance pipeline (provider → smoother → state machine)
/// into a WorkoutEngine during camera-mode workouts.
@Observable
final class CameraWorkoutController {
    private(set) var currentDepth: Double?
    private(set) var isTracking = false
    private(set) var isResting = false

    private let provider: any FaceDistanceProviding
    private weak var engine: WorkoutEngine?
    private var machine: RepCounterStateMachine?
    private var smoother = DistanceSmoother()
    private var consumeTask: Task<Void, Never>?

    init(provider: any FaceDistanceProviding, engine: WorkoutEngine) {
        self.provider = provider
        self.engine = engine
    }

    /// Starts the camera and detection. Safe to call during the countdown —
    /// the engine ignores reps until it is active, and the early start gives
    /// ARKit time to acquire the face.
    func start(config: RepDetectionConfig) {
        guard consumeTask == nil else { return }
        Log.detection.info(String(
            format: "Camera counting started — up %.3f m, down %.3f m, downThreshold %.0f%%, upThreshold %.0f%%, rest %.1f s",
            config.upDistance, config.downDistance, config.downThreshold * 100, config.upThreshold * 100, config.restThreshold
        ))
        machine = RepCounterStateMachine(config: config)
        smoother.reset()
        currentDepth = nil
        isResting = false
        provider.start()
        consumeTask = Task { [weak self] in
            guard let stream = self?.provider.samples else { return }
            for await sample in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(sample)
            }
        }
    }

    func stop() {
        guard consumeTask != nil else { return }
        Log.detection.info("Camera counting stopped")
        consumeTask?.cancel()
        consumeTask = nil
        provider.stop()
        machine = nil
        currentDepth = nil
        isTracking = false
        isResting = false
    }

    private func handle(_ sample: DistanceSample) {
        guard var machine else { return }
        let smoothedDistance = smoother.smooth(sample.distance)
        let events = machine.process(DistanceSample(distance: smoothedDistance, timestamp: sample.timestamp))
        self.machine = machine
        currentDepth = machine.currentDepth
        isTracking = smoothedDistance != nil

        for event in events {
            switch event {
            case .repCompleted(let count):
                Log.detection.debug("Rep \(count) detected")
                isResting = false
                engine?.recordRep()
            case .restDetected:
                Log.detection.info("Rest detected — set will split on next rep")
                isResting = true
            case .partialRepRejected:
                Log.detection.debug("Partial rep rejected (didn't reach down threshold)")
            case .faceLost:
                Log.detection.warning("Tracking lost mid-workout")
            case .faceReacquired:
                Log.detection.debug("Tracking reacquired")
            case .reachedBottom:
                break
            }
        }
    }
}
