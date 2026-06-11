//
//  DetectionCoreTests.swift
//  PushBroTests
//

import Foundation
import Testing
@testable import PushBro

/// Builds synthetic 60 Hz distance traces in normalized-depth terms and
/// converts them to meters using a fixed calibration.
private struct TraceBuilder {
    static let calibration = CalibrationProfile(upDistance: 0.45, downDistance: 0.15, createdAt: .distantPast)

    var samples: [DistanceSample] = []
    private(set) var time: TimeInterval = 0
    private let dt = 1.0 / 60
    /// Deterministic LCG so "noise" is reproducible.
    private var noiseState: UInt64 = 0x9E3779B97F4A7C15
    var noiseAmplitude = 0.0

    private mutating func noise() -> Double {
        noiseState = noiseState &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(noiseState >> 11) / Double(UInt64.max >> 11)
        return (unit * 2 - 1) * noiseAmplitude
    }

    private mutating func append(depth: Double) {
        let distance = Self.calibration.upDistance - depth * Self.calibration.range + noise()
        samples.append(DistanceSample(distance: distance, timestamp: time))
        time += dt
    }

    mutating func hold(depth: Double, duration: TimeInterval) {
        for _ in 0..<Int(duration / dt) {
            append(depth: depth)
        }
    }

    mutating func ramp(from: Double, to: Double, duration: TimeInterval) {
        let steps = Int(duration / dt)
        for step in 0..<steps {
            append(depth: from + (to - from) * Double(step) / Double(steps))
        }
    }

    mutating func rep(depth: Double, halfDuration: TimeInterval = 0.5) {
        ramp(from: 0, to: depth, duration: halfDuration)
        ramp(from: depth, to: 0, duration: halfDuration)
    }

    mutating func lost(duration: TimeInterval) {
        for _ in 0..<Int(duration / dt) {
            samples.append(DistanceSample(distance: nil, timestamp: time))
            time += dt
        }
    }
}

private func runTrace(
    _ samples: [DistanceSample],
    downThreshold: Double = Difficulty.medium.downThreshold,
    restThreshold: TimeInterval = 4.0,
    smoothed: Bool = true
) -> (machine: RepCounterStateMachine, events: [RepEvent]) {
    let config = RepDetectionConfig(
        calibration: TraceBuilder.calibration,
        downThreshold: downThreshold,
        restThreshold: restThreshold
    )
    var machine = RepCounterStateMachine(config: config)
    var smoother = DistanceSmoother()
    var events: [RepEvent] = []
    for sample in samples {
        let input = smoothed
            ? DistanceSample(distance: smoother.smooth(sample.distance), timestamp: sample.timestamp)
            : sample
        events.append(contentsOf: machine.process(input))
    }
    return (machine, events)
}

private func repCompletions(_ events: [RepEvent]) -> Int {
    events.count { if case .repCompleted = $0 { true } else { false } }
}

struct DetectionCoreTests {
    @Test func cleanRepsAllCount() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        for _ in 0..<10 {
            trace.rep(depth: 0.95)
        }
        let (machine, events) = runTrace(trace.samples)
        #expect(repCompletions(events) == 10)
        #expect(machine.repCount == 10)
        #expect(!events.contains(.partialRepRejected))
        #expect(!events.contains(.faceLost))
    }

    @Test func noisyRepsStillCountExactly() {
        var trace = TraceBuilder()
        trace.noiseAmplitude = 0.008 // ±8 mm sensor noise
        trace.hold(depth: 0, duration: 1)
        for _ in 0..<10 {
            trace.rep(depth: 0.95)
        }
        trace.hold(depth: 0, duration: 1)
        let (_, events) = runTrace(trace.samples)
        #expect(repCompletions(events) == 10)
    }

    @Test func partialRepsAreRejected() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        for _ in 0..<5 {
            trace.rep(depth: 0.5) // medium needs 0.75
        }
        let (_, events) = runTrace(trace.samples)
        #expect(repCompletions(events) == 0)
        #expect(events.contains(.partialRepRejected))
    }

    @Test func bouncingAtBottomCountsOnce() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        trace.ramp(from: 0, to: 0.85, duration: 0.5)
        // Wobble around the down threshold without reaching the up zone.
        for _ in 0..<3 {
            trace.ramp(from: 0.85, to: 0.55, duration: 0.3)
            trace.ramp(from: 0.55, to: 0.85, duration: 0.3)
        }
        trace.ramp(from: 0.85, to: 0, duration: 0.5)
        trace.hold(depth: 0, duration: 0.5)
        let (_, events) = runTrace(trace.samples)
        #expect(repCompletions(events) == 1)
    }

    @Test func deepFaceLossCountsAsBottom() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        // Descend deep enough that even the smoothed (lagging) depth is past
        // the 0.8 × 0.75 = 0.6 cutoff, then the sensor loses the chin.
        trace.ramp(from: 0, to: 0.75, duration: 0.5)
        trace.lost(duration: 1.0)
        trace.hold(depth: 0.1, duration: 0.5) // back up, reacquired
        let (_, events) = runTrace(trace.samples)
        #expect(events.contains(.faceLost))
        #expect(events.contains(.faceReacquired))
        #expect(repCompletions(events) == 1)
    }

    @Test func shallowFaceLossDoesNotCount() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        trace.ramp(from: 0, to: 0.4, duration: 0.5) // below 0.6 cutoff
        trace.lost(duration: 1.0)
        trace.hold(depth: 0.1, duration: 1)
        let (_, events) = runTrace(trace.samples)
        #expect(repCompletions(events) == 0)
    }

    @Test func briefDropoutIsIgnored() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        trace.ramp(from: 0, to: 0.95, duration: 0.5)
        trace.lost(duration: 0.2) // under the 0.5 s grace
        trace.ramp(from: 0.95, to: 0, duration: 0.5)
        trace.hold(depth: 0, duration: 0.5)
        let (_, events) = runTrace(trace.samples)
        #expect(!events.contains(.faceLost))
        #expect(repCompletions(events) == 1)
    }

    @Test func restDetectedOncePerDwell() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        trace.rep(depth: 0.95)
        trace.hold(depth: 0, duration: 8) // rest threshold 4 s — one event, not many
        trace.rep(depth: 0.95)
        trace.hold(depth: 0, duration: 6) // second dwell — second event
        let (_, events) = runTrace(trace.samples)
        #expect(events.count { $0 == .restDetected } == 2)
        #expect(repCompletions(events) == 2)
    }

    @Test func faceLostRestDetected() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        trace.rep(depth: 0.95)
        trace.lost(duration: 6)
        let (_, events) = runTrace(trace.samples)
        #expect(events.count { $0 == .restDetected } == 1)
    }

    @Test func difficultyChangesWhatCounts() {
        var trace = TraceBuilder()
        trace.hold(depth: 0, duration: 1)
        for _ in 0..<5 {
            trace.rep(depth: 0.65)
        }
        let easy = runTrace(trace.samples, downThreshold: Difficulty.easy.downThreshold)
        let hard = runTrace(trace.samples, downThreshold: Difficulty.hard.downThreshold)
        #expect(repCompletions(easy.events) == 5)
        #expect(repCompletions(hard.events) == 0)
    }

    @Test func entersFrameMidRepWithoutPhantomCount() {
        var trace = TraceBuilder()
        // First samples are already deep — e.g. user fiddled with placement.
        trace.ramp(from: 0.9, to: 0, duration: 0.5)
        trace.hold(depth: 0, duration: 1)
        trace.rep(depth: 0.95)
        let (_, events) = runTrace(trace.samples)
        #expect(repCompletions(events) == 1) // initial rise is not a rep
    }

    @Test func depthMappingAndClamping() {
        let config = RepDetectionConfig(calibration: TraceBuilder.calibration, downThreshold: 0.75, restThreshold: 4)
        #expect(abs(config.depth(forDistance: 0.45)) < 0.0001)
        #expect(abs(config.depth(forDistance: 0.15) - 1) < 0.0001)
        #expect(abs(config.depth(forDistance: 0.30) - 0.5) < 0.0001)
        #expect(abs(config.depth(forDistance: 2.0) - -0.5) < 0.0001) // clamped
        #expect(abs(config.depth(forDistance: 0.0) - 1.5) < 0.0001)  // clamped
        #expect(abs(config.upThreshold - 0.35) < 0.0001)
    }

    @Test func smootherKillsSpikesAndResetsOnLoss() {
        var smoother = DistanceSmoother()
        for _ in 0..<10 {
            _ = smoother.smooth(0.45)
        }
        // A single-frame spike to 0.9 must not move the output much.
        let spiked = smoother.smooth(0.9)
        #expect(abs((spiked ?? 0) - 0.45) < 0.01)

        #expect(smoother.smooth(nil) == nil)
        // After reset the next value isn't dragged toward history.
        #expect(smoother.smooth(0.2) == 0.2)
    }
}
