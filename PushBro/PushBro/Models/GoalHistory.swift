//
//  GoalHistory.swift
//  PushBro
//

import Foundation

struct GoalChange: Codable, Equatable {
    var date: Date
    var goal: Int
}

/// Record of daily-goal changes over time, so each day is judged against the
/// goal that was in effect that day instead of rewriting history whenever
/// the goal moves.
struct GoalHistory: Codable, Equatable {
    private(set) var changes: [GoalChange] = []

    static func decode(fromJSON json: String) -> GoalHistory? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GoalHistory.self, from: data)
    }

    func encodedJSON() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Appends a change. Multiple changes on the same day collapse to the
    /// final value (fiddling with the stepper shouldn't litter history), and
    /// no-op changes are dropped.
    mutating func record(goal: Int, at date: Date = .now, calendar: Calendar = .current) {
        guard goal > 0 else { return }
        while let last = changes.last, calendar.isDate(last.date, inSameDayAs: date) {
            changes.removeLast()
        }
        guard changes.last?.goal != goal else { return }
        changes.append(GoalChange(date: date, goal: goal))
    }

    /// The goal in effect on a given day: the latest change at or before the
    /// end of that day. Days before the first change use the first known
    /// goal; an empty history uses the fallback.
    func goal(on day: Date, calendar: Calendar = .current, fallback: Int) -> Int {
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else {
            return fallback
        }
        if let applicable = changes.last(where: { $0.date < endOfDay }) {
            return applicable.goal
        }
        return changes.first?.goal ?? fallback
    }
}

/// UserDefaults-backed access to the goal history.
nonisolated enum GoalHistoryStore {
    static func load() -> GoalHistory {
        GoalHistory.decode(fromJSON: UserDefaults.standard.string(forKey: AppSettings.goalHistoryJSONKey) ?? "")
            ?? GoalHistory()
    }

    /// Call from onChange(of: dailyGoal). The first recorded change seeds
    /// history with the previous value back to the beginning of time, so
    /// days before tracking started are judged by the goal they actually had.
    static func recordChange(from oldGoal: Int, to newGoal: Int) {
        var history = load()
        if history.changes.isEmpty, oldGoal > 0 {
            history.record(goal: oldGoal, at: .distantPast)
        }
        history.record(goal: newGoal)
        UserDefaults.standard.set(history.encodedJSON(), forKey: AppSettings.goalHistoryJSONKey)
        Log.data.info("Daily goal changed \(oldGoal) → \(newGoal) (history: \(history.changes.count) entries)")
    }
}
