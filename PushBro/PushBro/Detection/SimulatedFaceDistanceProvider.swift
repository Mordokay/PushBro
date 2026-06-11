//
//  SimulatedFaceDistanceProvider.swift
//  PushBro
//

import Foundation

/// Generates an endless loop of synthetic pushups (with a rest every five)
/// so camera mode and calibration are fully exercisable in the Simulator.
final class SimulatedFaceDistanceProvider: FaceDistanceProviding {
    let samples: AsyncStream<DistanceSample>
    private let continuation: AsyncStream<DistanceSample>.Continuation
    private var task: Task<Void, Never>?

    /// Matches what calibration should capture: up 0.45 m, down 0.15 m.
    static let upDistance = 0.45
    static let downDistance = 0.15

    init() {
        (samples, continuation) = AsyncStream.makeStream(
            of: DistanceSample.self,
            bufferingPolicy: .bufferingNewest(8)
        )
    }

    func start() {
        guard task == nil else { return }
        task = Task { [continuation] in
            var time = 0.0
            let dt = 1.0 / 30
            let repPeriod = 2.0
            let restEvery = 5
            let restDuration = 6.0
            let cycle = Double(restEvery) * repPeriod + restDuration

            while !Task.isCancelled {
                let phase = time.truncatingRemainder(dividingBy: cycle)
                let depth: Double
                if phase < Double(restEvery) * repPeriod {
                    depth = (1 - cos(2 * .pi * phase / repPeriod)) / 2
                } else {
                    depth = 0 // resting up
                }
                let distance = Self.upDistance - depth * (Self.upDistance - Self.downDistance)
                continuation.yield(DistanceSample(distance: distance, timestamp: time))
                try? await Task.sleep(for: .milliseconds(Int(dt * 1000)))
                time += dt
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
        continuation.finish()
    }
}
