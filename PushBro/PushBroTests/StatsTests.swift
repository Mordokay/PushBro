//
//  StatsTests.swift
//  PushBroTests
//

import Foundation
import Testing
@testable import PushBro

struct StatsTests {
    private let calendar = Calendar.current

    private func day(_ offset: Int, from base: Date = Date(timeIntervalSince1970: 1_750_000_000)) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base))!
    }

    private func session(on date: Date, sets: [[Double]]) -> WorkoutSession {
        var cursor = date
        var workoutSets: [WorkoutSet] = []
        for (index, offsets) in sets.enumerated() {
            let end = cursor.addingTimeInterval(offsets.last ?? 0)
            workoutSets.append(WorkoutSet(index: index, startDate: cursor, endDate: end, repOffsets: offsets))
            cursor = end.addingTimeInterval(60)
        }
        let session = WorkoutSession(
            startDate: date,
            endDate: workoutSets.last?.endDate ?? date,
            mode: .manual,
            totalReps: sets.reduce(0) { $0 + $1.count }
        )
        session.sets = workoutSets
        return session
    }

    @Test func summaryAggregates() {
        let d0 = day(0)
        let sessions = [
            session(on: d0, sets: [[0, 2, 4, 6], [0, 3, 6]]),          // 7 reps, intervals 2,2,2 / 3,3
            session(on: day(1), sets: [[0, 1.5, 3, 4.5, 6, 7.5]]),     // 6 reps, intervals 1.5 ×5
        ]

        let summary = StatsCalculator.summarize(sessions)
        #expect(summary.totalReps == 13)
        #expect(summary.totalSessions == 2)
        #expect(summary.bestSetReps == 6)
        #expect(summary.bestDayReps == 7)
        #expect(summary.bestDayDate == d0)
        #expect(summary.fastestRepInterval == 1.5)
        // (2*3 + 3*2 + 1.5*5) / 10 = 1.95
        #expect(abs((summary.averageRepInterval ?? 0) - 1.95) < 0.0001)
    }

    @Test func dailyTotalsGroupByDay() {
        let sessions = [
            session(on: day(0), sets: [[0, 2]]),
            session(on: day(0).addingTimeInterval(3600 * 10), sets: [[0, 2, 4]]),
            session(on: day(1), sets: [[0]]),
        ]
        let totals = StatsCalculator.dailyTotals(sessions)
        #expect(totals[day(0)] == 5)
        #expect(totals[day(1)] == 1)
    }

    @Test func streaksCountConsecutiveGoalDays() {
        let today = day(0)
        // Goal 10: met today, yesterday, day-2; gap at day-3; met day-4..day-6 (3-day run).
        let totals: [Date: Int] = [
            day(0): 12,
            day(-1): 10,
            day(-2): 15,
            day(-3): 5,
            day(-4): 11,
            day(-5): 20,
            day(-6): 10,
        ]
        let streaks = StreakCalculator.streaks(dailyTotals: totals, goal: 10, today: today)
        #expect(streaks.current == 3)
        #expect(streaks.best == 3)
    }

    @Test func todayBelowGoalKeepsYesterdayStreakAlive() {
        let today = day(0)
        let totals: [Date: Int] = [
            day(0): 3,       // in progress, below goal
            day(-1): 50,
            day(-2): 60,
        ]
        let streaks = StreakCalculator.streaks(dailyTotals: totals, goal: 50, today: today)
        #expect(streaks.current == 2)
        #expect(streaks.best == 2)
    }

    @Test func brokenStreakIsZero() {
        let today = day(0)
        let totals: [Date: Int] = [day(-3): 50, day(-4): 50]
        let streaks = StreakCalculator.streaks(dailyTotals: totals, goal: 50, today: today)
        #expect(streaks.current == 0)
        #expect(streaks.best == 2)
    }

    @Test func periodStatsAggregateByDay() {
        let sessions = [
            session(on: day(0), sets: [[0, 2, 4, 6], [0, 3, 6]]),      // 7 reps, 2 sets, intervals 2,2,2,3,3
            session(on: day(0).addingTimeInterval(3600), sets: [[0, 2]]), // +2 reps, 1 set, interval 2
            session(on: day(-1), sets: [[0, 1, 2]]),                   // 3 reps, 1 set
        ]
        let stats = StatsCalculator.periodStats(sessions, since: day(-1), groupByWeek: false)

        #expect(stats.count == 2)
        #expect(stats[0].period == day(-1))
        #expect(stats[0].reps == 3)
        #expect(stats[1].reps == 9)
        #expect(stats[1].sets == 3)
        #expect(stats[1].averageRepsPerSet == 3)
        // intervals on day 0: 2,2,2,3,3,2 → avg 14/6
        #expect(abs((stats[1].averageSecondsPerRep ?? 0) - 14.0 / 6.0) < 0.0001)
    }

    @Test func periodStatsRespectSinceCutoffAndWeekGrouping() {
        let sessions = [
            session(on: day(0), sets: [[0, 1]]),
            session(on: day(-40), sets: [[0, 1, 2]]), // before cutoff
        ]
        let daily = StatsCalculator.periodStats(sessions, since: day(-30), groupByWeek: false)
        #expect(daily.count == 1)
        #expect(daily[0].reps == 2)

        let weekly = StatsCalculator.periodStats(sessions, since: day(-60), groupByWeek: true)
        #expect(weekly.reduce(0) { $0 + $1.reps } == 5)
        for stat in weekly {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: stat.period)?.start
            #expect(stat.period == weekStart)
        }
    }

    @Test func timeOfDayBucketsBySessionStart() {
        let base = day(0)
        let sessions = [
            session(on: base.addingTimeInterval(8 * 3600), sets: [[0, 1]]),      // morning, 2
            session(on: base.addingTimeInterval(13 * 3600), sets: [[0, 1, 2]]),  // afternoon, 3
            session(on: base.addingTimeInterval(23 * 3600), sets: [[0]]),        // night, 1
        ]
        let slices = StatsCalculator.timeOfDayDistribution(sessions, since: base)
        #expect(slices == [
            StatsCalculator.TimeOfDaySlice(name: "Morning", reps: 2),
            StatsCalculator.TimeOfDaySlice(name: "Afternoon", reps: 3),
            StatsCalculator.TimeOfDaySlice(name: "Night", reps: 1),
        ])
    }

    @Test func periodStatsTrackRestBetweenSets() {
        // session() inserts 60 s between consecutive sets.
        let sessions = [session(on: day(0), sets: [[0, 2, 4], [0, 3], [0, 1]])]
        let stats = StatsCalculator.periodStats(sessions, since: day(0), groupByWeek: false)
        #expect(stats.count == 1)
        #expect(stats[0].restCount == 2)
        #expect(abs((stats[0].averageRestSeconds ?? 0) - 60) < 0.0001)

        // Single-set sessions have no rests.
        let single = StatsCalculator.periodStats([session(on: day(0), sets: [[0, 2]])], since: day(0), groupByWeek: false)
        #expect(single[0].averageRestSeconds == nil)
    }

    @Test func cumulativeMonthCarriesTotalsForward() {
        let today = day(0)
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start else {
            Issue.record("no month interval")
            return
        }
        let dayOfMonth = calendar.component(.day, from: today)
        let sessions = [
            session(on: monthStart.addingTimeInterval(9 * 3600), sets: [[0, 1, 2]]), // 3 reps on day 1
            session(on: today.addingTimeInterval(9 * 3600), sets: [[0, 1]]),         // 2 reps today
        ]
        let points = StatsCalculator.cumulativeMonthProgress(sessions, today: today)
        #expect(points.count == dayOfMonth)
        #expect(points.first?.total == 3)
        #expect(points.last?.total == 5)
        if points.count > 2 {
            // Days in between carry the running total forward.
            #expect(points[points.count / 2].total == 3 || dayOfMonth <= 2)
        }
    }

    @Test func weekdayTotalsCoverFullWeekInLocaleOrder() {
        let sessions = [
            session(on: day(0), sets: [[0, 1]]),       // 2 reps
            session(on: day(-7), sets: [[0, 1, 2]]),   // 3 reps, same weekday
            session(on: day(-1), sets: [[0]]),         // 1 rep, previous weekday
        ]
        let slices = StatsCalculator.weekdayTotals(sessions, since: day(-10))
        #expect(slices.count == 7)
        #expect(slices.reduce(0) { $0 + $1.reps } == 6)
        #expect(slices.map(\.order) == Array(0..<7))

        let targetSymbol = calendar.shortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day(0)) - 1]
        #expect(slices.first { $0.name == targetSymbol }?.reps == 5)
    }

    @Test func goalHistoryTracksPerDayGoals() {
        var history = GoalHistory()
        // Empty history falls back.
        #expect(history.goal(on: day(0), fallback: 50) == 50)

        history.record(goal: 100, at: .distantPast)
        history.record(goal: 110, at: day(0).addingTimeInterval(10 * 3600)) // changed mid-today

        #expect(history.goal(on: day(-1), fallback: 50) == 100)
        #expect(history.goal(on: day(0), fallback: 50) == 110)
        #expect(history.goal(on: day(5), fallback: 50) == 110)
        // Days before the first change use the first known goal.
        #expect(history.goal(on: day(-400), fallback: 50) == 100)
    }

    @Test func goalHistoryCollapsesSameDayChanges() {
        var history = GoalHistory()
        let noon = day(0).addingTimeInterval(12 * 3600)
        history.record(goal: 100, at: .distantPast)
        history.record(goal: 105, at: noon)
        history.record(goal: 110, at: noon.addingTimeInterval(60))
        history.record(goal: 120, at: noon.addingTimeInterval(120))
        // Stepper fiddling collapses to the final value of the day.
        #expect(history.changes.count == 2)
        #expect(history.goal(on: day(0), fallback: 0) == 120)
        #expect(history.goal(on: day(-1), fallback: 0) == 100)

        // Reverting to the previous value the same day removes the change.
        history.record(goal: 100, at: noon.addingTimeInterval(180))
        #expect(history.changes.count == 1)

        // JSON round trip.
        let decoded = GoalHistory.decode(fromJSON: history.encodedJSON())
        #expect(decoded == history)
    }

    @Test func streaksUsePerDayGoals() {
        // 100 every day until yesterday; 110 from today.
        var history = GoalHistory()
        history.record(goal: 100, at: .distantPast)
        history.record(goal: 110, at: day(0))

        let totals: [Date: Int] = [
            day(-2): 100, // met under old goal
            day(-1): 105, // met under old goal, would fail under 110
            day(0): 110,  // met under new goal
        ]
        let streaks = StreakCalculator.streaks(
            dailyTotals: totals,
            goalProvider: { history.goal(on: $0, fallback: 0) },
            today: day(0)
        )
        #expect(streaks.current == 3)
        #expect(streaks.best == 3)

        // A flat 110 goal would have broken the streak at day(-1).
        let flat = StreakCalculator.streaks(dailyTotals: totals, goal: 110, today: day(0))
        #expect(flat.current == 1)
    }

    @Test func goalPaceBendsAtGoalChanges() {
        let today = day(0)
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
              let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count else {
            Issue.record("no month info")
            return
        }
        var history = GoalHistory()
        history.record(goal: 100, at: .distantPast)
        history.record(goal: 10, at: today) // experiment: dropped mid-month

        let pace = StatsCalculator.cumulativeGoalPace(history: history, fallbackGoal: 50, today: today)
        #expect(pace.count == daysInMonth)
        // Day 1 climbs at the old goal.
        #expect(pace.first?.total == 100)
        let dayOfMonth = calendar.component(.day, from: today)
        // Days before the change accumulate 100/day; today adds only 10.
        let expectedToday = (dayOfMonth - 1) * 100 + 10
        #expect(pace[dayOfMonth - 1].total == expectedToday)
        // Remaining days extend at the new goal.
        #expect(pace.last?.total == expectedToday + (daysInMonth - dayOfMonth) * 10)
        // Monotonically increasing.
        #expect(zip(pace, pace.dropFirst()).allSatisfy { $0.total < $1.total })

        // Empty history: flat fallback pace.
        let flat = StatsCalculator.cumulativeGoalPace(history: GoalHistory(), fallbackGoal: 50, today: today)
        #expect(flat.first?.total == 50)
        #expect(flat.last?.total == 50 * daysInMonth)
    }

    @Test func monthSeriesClipToAppStartDate() {
        let today = day(0)
        guard let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
              let daysInMonth = calendar.range(of: .day, in: .month, for: today)?.count else {
            Issue.record("no month info")
            return
        }
        let dayOfMonth = calendar.component(.day, from: today)
        // Started using the app "yesterday" (or today if the month just began).
        let start = calendar.date(byAdding: .day, value: dayOfMonth > 1 ? -1 : 0, to: today)!
        let clippedDays = dayOfMonth > 1 ? 2 : 1

        let pace = StatsCalculator.cumulativeGoalPace(
            history: GoalHistory(), fallbackGoal: 50, startDate: start, today: today
        )
        // Pace exists only from the start day through month end.
        let startDayOfMonth = calendar.component(.day, from: start)
        #expect(pace.count == daysInMonth - startDayOfMonth + 1)
        #expect(pace.first?.day == calendar.startOfDay(for: start))
        #expect(pace.first?.total == 50) // no debt for skipped days

        let sessions = [session(on: start, sets: [[0, 1, 2]])]
        let progress = StatsCalculator.cumulativeMonthProgress(sessions, startDate: start, today: today)
        #expect(progress.count == clippedDays)
        #expect(progress.first?.day == calendar.startOfDay(for: start))
        #expect(progress.last?.total == 3)

        // Start date before the month: no clipping.
        let unclipped = StatsCalculator.cumulativeGoalPace(
            history: GoalHistory(), fallbackGoal: 50, startDate: monthStart.addingTimeInterval(-86400 * 40), today: today
        )
        #expect(unclipped.count == daysInMonth)
    }

    @Test func emptyOrZeroGoalIsSafe() {
        #expect(StreakCalculator.streaks(dailyTotals: [:], goal: 50) == StreakCalculator.Streaks())
        #expect(StreakCalculator.streaks(dailyTotals: [day(0): 100], goal: 0) == StreakCalculator.Streaks())
        #expect(StatsCalculator.summarize([]) == StatsCalculator.Summary())
    }
}
