//
//  TrueDepthDistanceProvider.swift
//  PushBro
//

import AVFoundation
import Foundation

/// Streams the distance to whatever is directly above the phone using the raw
/// TrueDepth depth map — no face recognition involved. More robust than face
/// tracking for pushups: it doesn't care whether the chin, nose, or chest is
/// overhead, and it keeps measuring all the way down to the sensor's minimum
/// range instead of cutting out when the face becomes unrecognizable.
final class TrueDepthDistanceProvider: NSObject, FaceDistanceProviding {
    static var isSupported: Bool {
        AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }

    let samples: AsyncStream<DistanceSample>
    private let continuation: AsyncStream<DistanceSample>.Continuation
    private let session = AVCaptureSession()
    private let depthOutput = AVCaptureDepthDataOutput()
    /// All session work happens here; delegate callbacks arrive here too.
    private let sessionQueue = DispatchQueue(label: "com.greenSphereStudios.PushBro.truedepth")
    private nonisolated(unsafe) var isConfigured = false

    override init() {
        (samples, continuation) = AsyncStream.makeStream(
            of: DistanceSample.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        super.init()
    }

    func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                Log.detection.error("Camera permission denied — TrueDepth provider can't start")
                return
            }
            sessionQueue.async { [self] in
                configureIfNeeded()
                guard isConfigured else { return }
                if !session.isRunning {
                    session.startRunning()
                    Log.detection.info("TrueDepth depth capture running")
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
                Log.detection.info("TrueDepth depth capture stopped")
            }
        }
    }

    deinit {
        continuation.finish()
    }

    private nonisolated func configureIfNeeded() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            Log.detection.error("TrueDepth camera unavailable or input creation failed")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(depthOutput) else {
            session.commitConfiguration()
            Log.detection.error("TrueDepth session configuration rejected input/output")
            return
        }
        session.addInput(input)
        session.addOutput(depthOutput)
        // Raw, unfiltered depth: hole-filling would invent plausible-looking
        // values exactly when the subject drops below the minimum range — we
        // want those frames to read as "nothing tracked" instead.
        depthOutput.isFilteringEnabled = false
        depthOutput.setDelegate(self, callbackQueue: sessionQueue)
        session.commitConfiguration()
        isConfigured = true
        Log.detection.info("TrueDepth session configured (depth format: \(device.activeDepthDataFormat.map { String(describing: $0.formatDescription.mediaSubType) } ?? "default"))")
    }
}

extension TrueDepthDistanceProvider: AVCaptureDepthDataOutputDelegate {
    nonisolated func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        let depth = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData
            : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let distance = Self.nearestSubjectDistance(in: depth.depthDataMap)
        continuation.yield(DistanceSample(distance: distance, timestamp: timestamp.seconds))
    }

    /// Low-percentile depth of the frame's central region: the nearest
    /// substantial surface above the phone (face, chin, or chest). The
    /// ceiling sits outside the plausible band, so "nobody overhead" and
    /// "below minimum range" both come back nil — same semantics face
    /// tracking had for a lost face.
    private nonisolated static func nearestSubjectDistance(in map: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        // Central half of the frame, sampled on a coarse grid — plenty of
        // pixels for a robust estimate at a fraction of the cost.
        let xRange = Swift.stride(from: width / 4, to: width * 3 / 4, by: 4)
        let yRange = Swift.stride(from: height / 4, to: height * 3 / 4, by: 4)
        var values: [Float] = []
        values.reserveCapacity((width / 8) * (height / 8))

        for y in yRange {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in xRange {
                let value = row[x]
                // Plausible band for a person doing pushups over the phone.
                if value.isFinite, value > 0.05, value < 1.2 {
                    values.append(value)
                }
            }
        }

        // Demand a real surface, not a handful of noisy pixels.
        guard values.count >= 50 else { return nil }
        let sorted = values.sorted()
        return Double(sorted[sorted.count / 10])
    }
}
