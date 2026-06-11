//
//  FaceDistanceProvider.swift
//  PushBro
//

import Foundation

/// Source of face-distance samples. The ARKit implementation needs a real
/// device; a simulated implementation drives the Simulator and previews.
@MainActor
protocol FaceDistanceProviding: AnyObject {
    /// Single-consumer stream of samples at roughly camera frame rate.
    var samples: AsyncStream<DistanceSample> { get }
    func start()
    func stop()
}

@MainActor
enum FaceDistanceProviderFactory {
    /// Whether camera counting is possible in this environment.
    static var isCameraModeAvailable: Bool {
        #if targetEnvironment(simulator)
        true // simulated provider
        #else
        TrueDepthDistanceProvider.isSupported || ARFaceDistanceProvider.isSupported
        #endif
    }

    /// Prefers the raw TrueDepth depth map (tracks whatever is overhead, no
    /// face recognition needed); falls back to ARKit face tracking on A12+
    /// devices without TrueDepth hardware.
    static func make() -> (any FaceDistanceProviding)? {
        #if targetEnvironment(simulator)
        return SimulatedFaceDistanceProvider()
        #else
        if TrueDepthDistanceProvider.isSupported {
            return TrueDepthDistanceProvider()
        }
        if ARFaceDistanceProvider.isSupported {
            return ARFaceDistanceProvider()
        }
        return nil
        #endif
    }
}
