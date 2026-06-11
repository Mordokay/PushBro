//
//  RepDetectionConfig.swift
//  PushBro
//

import Foundation

/// Thresholds for the rep state machine, derived from calibration and the
/// difficulty setting. All depth values are normalized: 0 = calibrated up
/// position, 1 = calibrated down position.
struct RepDetectionConfig: Equatable {
    var upDistance: Double
    var downDistance: Double

    /// Depth the user must reach for a rep to count (difficulty slider).
    var downThreshold: Double
    /// Depth the user must rise back above to complete a rep / re-arm.
    /// Kept well below `downThreshold` — the gap is the hysteresis.
    var upThreshold: Double

    /// Seconds in the up zone (or untracked) before the set is considered over.
    var restThreshold: TimeInterval

    /// Continuous time in the up zone required before the machine arms.
    var armingDuration: TimeInterval = 0.3
    /// Nil-sample dropouts shorter than this are ignored.
    var faceLossGrace: TimeInterval = 0.5
    /// Face lost while past this fraction of `downThreshold` counts as
    /// reaching the bottom — the chin likely went below the sensor's
    /// minimum tracking range.
    var deepFaceLossFraction = 0.8

    init(calibration: CalibrationProfile, downThreshold: Double, restThreshold: TimeInterval) {
        self.upDistance = calibration.upDistance
        self.downDistance = calibration.downDistance
        self.downThreshold = downThreshold
        // Maps the presets 0.60/0.75/0.90 to 0.30/0.35/0.40.
        self.upThreshold = 0.1 + downThreshold / 3
        self.restThreshold = restThreshold
    }

    /// Normalized depth for a raw distance. Clamped so wild sensor values
    /// can't produce absurd depths.
    func depth(forDistance distance: Double) -> Double {
        let range = upDistance - downDistance
        guard range > 0 else { return 0 }
        let depth = (upDistance - distance) / range
        return min(1.5, max(-0.5, depth))
    }
}
