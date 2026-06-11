//
//  WorkoutSession.swift
//  PushBro
//

import Foundation
import SwiftData

enum WorkoutMode: String, Codable {
    case camera
    case manual
}

@Model
final class WorkoutSession {
    var startDate: Date
    var endDate: Date
    var modeRaw: String
    /// Denormalized so calendar queries never fault in sets.
    var totalReps: Int
    var healthKitWorkoutID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session)
    var sets: [WorkoutSet] = []

    var mode: WorkoutMode {
        get { WorkoutMode(rawValue: modeRaw) ?? .manual }
        set { modeRaw = newValue.rawValue }
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var orderedSets: [WorkoutSet] {
        sets.sorted { $0.index < $1.index }
    }

    init(startDate: Date, endDate: Date, mode: WorkoutMode, totalReps: Int = 0) {
        self.startDate = startDate
        self.endDate = endDate
        self.modeRaw = mode.rawValue
        self.totalReps = totalReps
    }
}
