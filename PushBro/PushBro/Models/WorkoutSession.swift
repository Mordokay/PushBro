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
    /// Heart rate from a paired watch: seconds since startDate + bpm, parallel arrays.
    var heartRateOffsets: [Double] = []
    var heartRateValues: [Double] = []
    /// Active energy computed by the watch's own sensor fusion, when available.
    var watchEnergyKcal: Double?

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

    var averageHeartRate: Double? {
        guard !heartRateValues.isEmpty else { return nil }
        return heartRateValues.reduce(0, +) / Double(heartRateValues.count)
    }

    init(startDate: Date, endDate: Date, mode: WorkoutMode, totalReps: Int = 0) {
        self.startDate = startDate
        self.endDate = endDate
        self.modeRaw = mode.rawValue
        self.totalReps = totalReps
    }
}
