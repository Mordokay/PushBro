//
//  DebugSeed.swift
//  PushBro
//

#if DEBUG
import Foundation
import SwiftData

/// Inserts ~6 weeks of plausible workout data for History/Stats development.
enum DebugSeed {
    static func populate(context: ModelContext, days: Int = 42) {
        var generator = SystemRandomNumberGenerator()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for dayOffset in 0..<days {
            // Skip ~25% of days so streak/heatmap gaps are visible.
            guard Int.random(in: 0..<4, using: &generator) != 0,
                  let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            let sessionCount = Int.random(in: 1...2, using: &generator)
            for sessionIndex in 0..<sessionCount {
                let start = day.addingTimeInterval(Double(8 + sessionIndex * 9) * 3600 + Double(Int.random(in: 0..<1800, using: &generator)))
                var sets: [WorkoutSet] = []
                var cursor = start
                let setCount = Int.random(in: 1...4, using: &generator)
                for setIndex in 0..<setCount {
                    let reps = Int.random(in: 5...25, using: &generator)
                    let pace = Double.random(in: 1.5...3.5, using: &generator)
                    let offsets = (0..<reps).map { Double($0) * pace }
                    let end = cursor.addingTimeInterval(offsets.last ?? 0)
                    sets.append(WorkoutSet(index: setIndex, startDate: cursor, endDate: end, repOffsets: offsets))
                    cursor = end.addingTimeInterval(Double.random(in: 20...90, using: &generator))
                }

                let session = WorkoutSession(
                    startDate: start,
                    endDate: sets.last?.endDate ?? start,
                    mode: Bool.random(using: &generator) ? .camera : .manual,
                    totalReps: sets.reduce(0) { $0 + $1.repCount }
                )
                session.sets = sets
                context.insert(session)
            }
        }
        try? context.save()
        Log.data.debug("Seeded \(days) days of demo workout data")
    }
}
#endif
