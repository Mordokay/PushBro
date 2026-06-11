//
//  ARFaceDistanceProvider.swift
//  PushBro
//

import ARKit
import Foundation
import simd

/// Streams the metric distance between the front (TrueDepth) camera and the
/// user's face using ARKit face tracking.
final class ARFaceDistanceProvider: NSObject, FaceDistanceProviding {
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    let samples: AsyncStream<DistanceSample>
    private let continuation: AsyncStream<DistanceSample>.Continuation
    private let session = ARSession()

    override init() {
        (samples, continuation) = AsyncStream.makeStream(
            of: DistanceSample.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        super.init()
        session.delegate = self
    }

    /// Delegate callbacks arrive on ARKit's serial queue, so plain vars are safe.
    private nonisolated(unsafe) var wasTracking = false

    func start() {
        Log.detection.info("ARKit face tracking starting (supported: \(Self.isSupported))")
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = false
        configuration.maximumNumberOfTrackedFaces = 1
        // providesAudioData stays false: the mic belongs to speech recognition.
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        Log.detection.info("ARKit face tracking stopped")
        session.pause()
    }

    deinit {
        continuation.finish()
    }
}

extension ARFaceDistanceProvider: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let distance: Double?
        if let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked {
            // Both transforms are world-space; the world origin drifts, so
            // only their difference is meaningful.
            let facePosition = face.transform.columns.3
            let cameraPosition = frame.camera.transform.columns.3
            distance = Double(simd_length(
                SIMD3(facePosition.x, facePosition.y, facePosition.z)
                    - SIMD3(cameraPosition.x, cameraPosition.y, cameraPosition.z)
            ))
        } else {
            distance = nil
        }

        let tracking = distance != nil
        if tracking != wasTracking {
            wasTracking = tracking
            if let distance {
                Log.detection.debug(String(format: "Face acquired at %.3f m", distance))
            } else {
                Log.detection.debug("Face tracking lost")
            }
        }

        continuation.yield(DistanceSample(distance: distance, timestamp: frame.timestamp))
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        Log.detection.error("ARSession failed: \(error.localizedDescription)")
        continuation.yield(DistanceSample(distance: nil, timestamp: Date().timeIntervalSinceReferenceDate))
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Log.detection.warning("ARSession interrupted (camera taken by another client or app backgrounded)")
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Log.detection.info("ARSession interruption ended")
    }
}
