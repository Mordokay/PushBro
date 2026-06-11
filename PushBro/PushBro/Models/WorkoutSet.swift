//
//  WorkoutSet.swift
//  PushBro
//

import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var index: Int
    var startDate: Date
    var endDate: Date
    /// Seconds since `startDate`, one entry per completed rep. Diffs give cadence.
    var repOffsets: [Double] = []
    /// Denormalized = repOffsets.count.
    var repCount: Int
    var session: WorkoutSession?

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Seconds between consecutive reps.
    var repIntervals: [Double] {
        guard repOffsets.count > 1 else { return [] }
        return zip(repOffsets.dropFirst(), repOffsets).map(-)
    }

    init(index: Int, startDate: Date, endDate: Date, repOffsets: [Double]) {
        self.index = index
        self.startDate = startDate
        self.endDate = endDate
        self.repOffsets = repOffsets
        self.repCount = repOffsets.count
    }
}
