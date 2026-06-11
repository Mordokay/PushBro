//
//  StreakCalculator.swift
//  PushBro
//

import Foundation

enum StreakCalculator {
    struct Streaks: Equatable {
        var current = 0
        var best = 0
    }

    /// A streak is consecutive days with total >= goal. Today not yet at goal
    /// doesn't break the current streak — it just doesn't count yet.
    static func streaks(
        dailyTotals: [Date: Int],
        goal: Int,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Streaks {
        guard goal > 0, !dailyTotals.isEmpty else { return Streaks() }

        let metDays = Set(
            dailyTotals.filter { $0.value >= goal }.keys.map { calendar.startOfDay(for: $0) }
        )
        guard !metDays.isEmpty else { return Streaks() }

        var best = 0
        for day in metDays {
            // Only count runs from their first day.
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day),
                  !metDays.contains(previous) else { continue }
            var length = 1
            var cursor = day
            while let next = calendar.date(byAdding: .day, value: 1, to: cursor), metDays.contains(next) {
                length += 1
                cursor = next
            }
            best = max(best, length)
        }

        var current = 0
        var cursor = calendar.startOfDay(for: today)
        if !metDays.contains(cursor) {
            // Grace for today: start counting from yesterday.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                return Streaks(current: 0, best: best)
            }
            cursor = yesterday
        }
        while metDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return Streaks(current: current, best: best)
    }
}
