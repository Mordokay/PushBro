//
//  RepEvent.swift
//  PushBro
//

import Foundation

enum RepEvent: Equatable {
    case repCompleted(count: Int)
    /// The down threshold was crossed; the rep completes on the way back up.
    case reachedBottom
    /// User came back up without reaching the down threshold.
    case partialRepRejected
    /// User stayed up (or untracked) past the rest threshold.
    case restDetected
    case faceLost
    case faceReacquired
}
