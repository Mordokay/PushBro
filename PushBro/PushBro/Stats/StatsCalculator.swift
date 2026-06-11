//
//  StatsCalculator.swift
//  PushBro
//

import Foundation

/// Pure aggregations over persisted sessions. Kept framework-free for testability.
enum StatsCalculator {
    struct Summary: Equatable {
        var totalReps = 0
        var totalSessions = 0
        var bestSetReps = 0
        var bestDayReps = 0
        var bestDayDate: Date?
        var longestSessionDuration: TimeInterval = 0
        /// Mean seconds between consecutive reps within sets.
        var averageRepInterval: TimeInterval?
        var fastestRepInterval: TimeInterval?
    }

    static func summarize(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> Summary {
        var summary = Summary()
        summary.totalSessions = sessions.count

        var intervalSum = 0.0
        var intervalCount = 0

        for session in sessions {
            summary.totalReps += session.totalReps
            summary.longestSessionDuration = max(summary.longestSessionDuration, session.duration)
            for set in session.sets {
                summary.bestSetReps = max(summary.bestSetReps, set.repCount)
                for interval in set.repIntervals where interval > 0 {
                    intervalSum += interval
                    intervalCount += 1
                    if interval < (summary.fastestRepInterval ?? .infinity) {
                        summary.fastestRepInterval = interval
                    }
                }
            }
        }

        if intervalCount > 0 {
            summary.averageRepInterval = intervalSum / Double(intervalCount)
        }

        if let best = dailyTotals(sessions, calendar: calendar).max(by: { $0.value < $1.value }) {
            summary.bestDayReps = best.value
            summary.bestDayDate = best.key
        }

        return summary
    }

    /// Reps per start-of-day, for the calendar heatmap and streaks.
    static func dailyTotals(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> [Date: Int] {
        sessions.reduce(into: [:]) { totals, session in
            totals[calendar.startOfDay(for: session.startDate), default: 0] += session.totalReps
        }
    }

    // MARK: - Chart data

    /// One aggregation bucket (a day, or a week in long ranges) for charts.
    struct PeriodStats: Identifiable, Equatable {
        let period: Date
        var reps = 0
        var sets = 0
        var repIntervalSum = 0.0
        var repIntervalCount = 0
        var restSum = 0.0
        var restCount = 0

        var id: Date { period }
        var averageSecondsPerRep: Double? {
            repIntervalCount > 0 ? repIntervalSum / Double(repIntervalCount) : nil
        }
        var averageRepsPerSet: Double? {
            sets > 0 ? Double(reps) / Double(sets) : nil
        }
        var averageRestSeconds: Double? {
            restCount > 0 ? restSum / Double(restCount) : nil
        }
    }

    static func periodStats(
        _ sessions: [WorkoutSession],
        since: Date,
        groupByWeek: Bool,
        calendar: Calendar = .current
    ) -> [PeriodStats] {
        var byPeriod: [Date: PeriodStats] = [:]
        for session in sessions where session.startDate >= since {
            let bucket = groupByWeek
                ? calendar.dateInterval(of: .weekOfYear, for: session.startDate)?.start
                    ?? calendar.startOfDay(for: session.startDate)
                : calendar.startOfDay(for: session.startDate)
            var stats = byPeriod[bucket] ?? PeriodStats(period: bucket)
            stats.reps += session.totalReps
            stats.sets += session.sets.count
            let orderedSets = session.orderedSets
            for set in orderedSets {
                for interval in set.repIntervals where interval > 0 {
                    stats.repIntervalSum += interval
                    stats.repIntervalCount += 1
                }
            }
            for (current, next) in zip(orderedSets, orderedSets.dropFirst()) {
                let rest = next.startDate.timeIntervalSince(current.endDate)
                if rest > 0 {
                    stats.restSum += rest
                    stats.restCount += 1
                }
            }
            byPeriod[bucket] = stats
        }
        return byPeriod.values.sorted { $0.period < $1.period }
    }

    struct TimeOfDaySlice: Identifiable, Equatable {
        let name: String
        let reps: Int
        var id: String { name }
    }

    /// Reps grouped into morning/afternoon/evening/night by session start.
    static func timeOfDayDistribution(
        _ sessions: [WorkoutSession],
        since: Date,
        calendar: Calendar = .current
    ) -> [TimeOfDaySlice] {
        var buckets: [String: Int] = [:]
        for session in sessions where session.startDate >= since {
            let hour = calendar.component(.hour, from: session.startDate)
            let name = switch hour {
            case 5..<12: "Morning"
            case 12..<17: "Afternoon"
            case 17..<22: "Evening"
            default: "Night"
            }
            buckets[name, default: 0] += session.totalReps
        }
        let displayOrder = ["Morning", "Afternoon", "Evening", "Night"]
        return displayOrder.compactMap { name in
            buckets[name].map { TimeOfDaySlice(name: name, reps: $0) }
        }
    }

    struct CumulativePoint: Identifiable, Equatable {
        let day: Date
        let total: Int
        var id: Date { day }
    }

    /// Running rep total for each day of the current calendar month, up to
    /// (and including) today. Days without workouts carry the total forward.
    /// `startDate` clips the series — days before the user started using the
    /// app don't appear at all.
    static func cumulativeMonthProgress(
        _ sessions: [WorkoutSession],
        startDate: Date? = nil,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [CumulativePoint] {
        guard let month = calendar.dateInterval(of: .month, for: today) else { return [] }
        let totals = dailyTotals(sessions.filter { month.contains($0.startDate) }, calendar: calendar)

        var points: [CumulativePoint] = []
        var running = 0
        var day = month.start
        if let startDate {
            day = max(day, calendar.startOfDay(for: startDate))
        }
        let endOfToday = calendar.startOfDay(for: today)
        while day <= endOfToday {
            running += totals[day] ?? 0
            points.append(CumulativePoint(day: day, total: running))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    /// Cumulative goal pace for the current calendar month, honoring the
    /// goal in effect on each day — the line's slope changes where the goal
    /// changed, and future days extend at the latest goal. `startDate` clips
    /// the series so no pace is demanded for days before the app was used.
    static func cumulativeGoalPace(
        history: GoalHistory,
        fallbackGoal: Int,
        startDate: Date? = nil,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [CumulativePoint] {
        guard let month = calendar.dateInterval(of: .month, for: today) else { return [] }
        var points: [CumulativePoint] = []
        var running = 0
        var day = month.start
        if let startDate {
            day = max(day, calendar.startOfDay(for: startDate))
        }
        while day < month.end {
            running += history.goal(on: day, calendar: calendar, fallback: fallbackGoal)
            points.append(CumulativePoint(day: day, total: running))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    struct WeekdaySlice: Identifiable, Equatable {
        let name: String
        let reps: Int
        /// Position in the locale's week, starting at the locale's first weekday.
        let order: Int
        var id: Int { order }
    }

    /// Total reps per weekday, in the locale's week order. Zero days are
    /// included so the chart shows the full week's shape.
    static func weekdayTotals(
        _ sessions: [WorkoutSession],
        since: Date,
        calendar: Calendar = .current
    ) -> [WeekdaySlice] {
        var byWeekday: [Int: Int] = [:] // Calendar weekday component, 1...7
        for session in sessions where session.startDate >= since {
            byWeekday[calendar.component(.weekday, from: session.startDate), default: 0] += session.totalReps
        }
        let symbols = calendar.shortStandaloneWeekdaySymbols // Sun-first, 0-indexed
        return (0..<7).map { position in
            let symbolIndex = (calendar.firstWeekday - 1 + position) % 7
            return WeekdaySlice(name: symbols[symbolIndex], reps: byWeekday[symbolIndex + 1] ?? 0, order: position)
        }
    }
}
