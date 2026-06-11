//
//  DistanceSample.swift
//  PushBro
//

import Foundation

/// One face-distance measurement. `distance` is meters from camera to face;
/// nil means the face is not currently tracked.
struct DistanceSample: Equatable {
    var distance: Double?
    var timestamp: TimeInterval
}
