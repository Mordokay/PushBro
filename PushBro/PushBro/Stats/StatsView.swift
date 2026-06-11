//
//  StatsView.swift
//  PushBro
//

import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query private var sessions: [WorkoutSession]
    @AppStorage(AppSettings.dailyGoalKey) private var dailyGoal = AppSettings.defaultDailyGoal

    @State private var range: StatsRange = .month

    enum StatsRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case sixMonths = "6 Months"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .sixMonths: 182
            }
        }

        /// Long ranges aggregate per week so bars stay readable.
        var groupsByWeek: Bool { self == .sixMonths }

        var chartUnit: Calendar.Component { groupsByWeek ? .weekOfYear : .day }
    }

    private var rangeStart: Date {
        Calendar.current.date(byAdding: .day, value: -(range.days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No stats yet",
                        systemImage: "chart.bar",
                        description: Text("Stats appear after your first session.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Stats")
        }
    }

    private var content: some View {
        let stats = StatsCalculator.periodStats(sessions, since: rangeStart, groupByWeek: range.groupsByWeek)
        let slices = StatsCalculator.timeOfDayDistribution(sessions, since: rangeStart)

        return ScrollView {
            VStack(spacing: 16) {
                monthProgressCard

                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                if stats.isEmpty {
                    ContentUnavailableView(
                        "Nothing in this period",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Pick a longer range or do some pushups!")
                    )
                    .frame(height: 220)
                } else {
                    volumeCard(stats)
                    paceCard(stats)
                    setSizeCard(stats)
                    restCard(stats)
                    weekdayCard
                    timeOfDayCard(slices)
                }

                allTimeGrid
            }
            .padding()
        }
    }

    // MARK: - Month progress

    /// When the user started using the app: the recorded first launch, or
    /// the earliest session if that's older (covers pre-tracking installs).
    /// Month charts ignore days before this entirely.
    private var appStartDate: Date {
        let stored = UserDefaults.standard.double(forKey: AppSettings.firstLaunchDateKey)
        let firstLaunch = stored > 0 ? Date(timeIntervalSince1970: stored) : .now
        let firstSession = sessions.map(\.startDate).min() ?? firstLaunch
        return min(firstLaunch, firstSession)
    }

    private var monthProgressCard: some View {
        let calendar = Calendar.current
        let history = GoalHistoryStore.load()
        let start = appStartDate
        let points = StatsCalculator.cumulativeMonthProgress(sessions, startDate: start)
        let pace = StatsCalculator.cumulativeGoalPace(history: history, fallbackGoal: dailyGoal, startDate: start)
        let currentTotal = points.last?.total ?? 0
        let today = calendar.startOfDay(for: .now)
        let paceTarget = pace.first { calendar.isDate($0.day, inSameDayAs: today) }?.total
            ?? pace.last?.total ?? 0
        let onPace = currentTotal >= paceTarget

        return chartCard(
            title: "This month",
            icon: "chart.line.uptrend.xyaxis",
            caption: "\(currentTotal) reps so far — goal pace is \(paceTarget) by today. \(onPace ? "You're ahead! 🔥" : "Time to catch up.")"
        ) {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Reps", point.total)
                    )
                    .foregroundStyle(.green.opacity(0.15))
                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Reps", point.total),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                // Pace honors the goal in effect each day, so the slope
                // bends where the goal changed.
                ForEach(pace) { point in
                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Reps", point.total),
                        series: .value("Series", "Goal pace")
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
        }
    }

    // MARK: - Rest

    private func restCard(_ stats: [StatsCalculator.PeriodStats]) -> some View {
        let rested = stats.filter { $0.averageRestSeconds != nil }
        return chartCard(
            title: "Rest between sets",
            icon: "pause.circle.fill",
            caption: "Average rest duration — shorter rests mean faster recovery."
        ) {
            Chart(rested) { stat in
                LineMark(
                    x: .value("Date", stat.period, unit: range.chartUnit),
                    y: .value("Rest (s)", stat.averageRestSeconds ?? 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.orange)
                PointMark(
                    x: .value("Date", stat.period, unit: range.chartUnit),
                    y: .value("Rest (s)", stat.averageRestSeconds ?? 0)
                )
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Weekday breakdown

    private var weekdayCard: some View {
        let slices = StatsCalculator.weekdayTotals(sessions, since: rangeStart)
        let best = slices.map(\.reps).max() ?? 0
        return chartCard(
            title: "Weekday breakdown",
            icon: "calendar",
            caption: "Total reps by weekday — spot the days you skip."
        ) {
            Chart(slices) { slice in
                BarMark(
                    x: .value("Day", slice.name),
                    y: .value("Reps", slice.reps)
                )
                .foregroundStyle(slice.reps == best && best > 0 ? Color.mint : Color.mint.opacity(0.55))
                .cornerRadius(4)
            }
            .chartXScale(domain: slices.map(\.name))
        }
    }

    // MARK: - Volume

    /// The goal in effect for a chart period — the day's recorded goal, or
    /// the sum of the week's daily goals when aggregating weekly.
    private func goal(for period: Date, history: GoalHistory) -> Int {
        let calendar = Calendar.current
        guard range.groupsByWeek else {
            return history.goal(on: period, fallback: dailyGoal)
        }
        return (0..<7).reduce(0) { sum, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: period) else { return sum }
            return sum + history.goal(on: day, fallback: dailyGoal)
        }
    }

    private func volumeCard(_ stats: [StatsCalculator.PeriodStats]) -> some View {
        let history = GoalHistoryStore.load()
        let currentGoal = dailyGoal * (range.groupsByWeek ? 7 : 1)
        return chartCard(
            title: "Volume",
            icon: "chart.bar.fill",
            caption: "Blue is reps toward that \(range.groupsByWeek ? "week" : "day")'s goal, green is extra, faded red is what was missed."
        ) {
            Chart {
                // No if/else in chart content: conditional ChartContent hits
                // a Charts runtime metadata crash. Zero-height marks render
                // nothing, so both segments are emitted unconditionally.
                ForEach(stats) { stat in
                    let goal = goal(for: stat.period, history: history)
                    let achieved = min(stat.reps, goal)
                    let extra = max(0, stat.reps - goal)
                    let missed = max(0, goal - stat.reps)
                    BarMark(
                        x: .value("Date", stat.period, unit: range.chartUnit),
                        y: .value("Reps", achieved)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(2)
                    .annotation(position: .overlay) {
                        Text(stat.reps > 0 ? "\(stat.reps)" : "")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    BarMark(
                        x: .value("Date", stat.period, unit: range.chartUnit),
                        y: .value("Reps", extra + missed)
                    )
                    .foregroundStyle(extra > 0 ? Color.green : Color.red.opacity(0.22))
                    .cornerRadius(2)
                }
                RuleMark(y: .value("Goal", currentGoal))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .topTrailing) {
                        Text("Goal \(currentGoal)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
            }
        }
    }

    // MARK: - Pace

    private func paceCard(_ stats: [StatsCalculator.PeriodStats]) -> some View {
        let paced = stats.filter { $0.averageSecondsPerRep != nil }
        return chartCard(
            title: "Pace",
            icon: "metronome.fill",
            caption: "Average seconds per rep — lower means faster reps."
        ) {
            Chart(paced) { stat in
                LineMark(
                    x: .value("Date", stat.period, unit: range.chartUnit),
                    y: .value("s/rep", stat.averageSecondsPerRep ?? 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.teal)
                PointMark(
                    x: .value("Date", stat.period, unit: range.chartUnit),
                    y: .value("s/rep", stat.averageSecondsPerRep ?? 0)
                )
                .foregroundStyle(.teal)
            }
        }
    }

    // MARK: - Set size

    private func setSizeCard(_ stats: [StatsCalculator.PeriodStats]) -> some View {
        let sized = stats.filter { $0.averageRepsPerSet != nil }
        return chartCard(
            title: "Set size",
            icon: "square.stack.3d.up.fill",
            caption: "Average reps per set — bigger sets mean growing endurance."
        ) {
            Chart(sized) { stat in
                LineMark(
                    x: .value("Date", stat.period, unit: range.chartUnit),
                    y: .value("Reps/set", stat.averageRepsPerSet ?? 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.purple)
                PointMark(
                    x: .value("Date", stat.period, unit: range.chartUnit),
                    y: .value("Reps/set", stat.averageRepsPerSet ?? 0)
                )
                .foregroundStyle(.purple)
            }
        }
    }

    // MARK: - Time of day

    private func timeOfDayCard(_ slices: [StatsCalculator.TimeOfDaySlice]) -> some View {
        let total = slices.reduce(0) { $0 + $1.reps }
        return chartCard(
            title: "Time of day",
            icon: "clock.fill",
            caption: "When you do your pushups."
        ) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Reps", slice.reps),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Time", slice.name))
                .annotation(position: .overlay) {
                    if total > 0, Double(slice.reps) / Double(total) >= 0.12 {
                        Text("\(slice.reps)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Morning": Color.yellow,
                "Afternoon": Color.orange,
                "Evening": Color.indigo,
                "Night": Color.purple,
            ])
            .chartLegend(position: .bottom, spacing: 12)
        }
    }

    // MARK: - All-time records

    private var allTimeGrid: some View {
        let summary = StatsCalculator.summarize(sessions)
        let history = GoalHistoryStore.load()
        let streaks = StreakCalculator.streaks(
            dailyTotals: StatsCalculator.dailyTotals(sessions),
            goalProvider: { history.goal(on: $0, fallback: dailyGoal) }
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("All time")
                .font(.title3.weight(.bold))
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "Current streak", value: "\(streaks.current)", unit: streaks.current == 1 ? "day" : "days", icon: "flame.fill")
                StatCard(title: "Best streak", value: "\(streaks.best)", unit: streaks.best == 1 ? "day" : "days", icon: "trophy.fill")
                StatCard(title: "Total pushups", value: "\(summary.totalReps)", unit: nil, icon: "sum")
                StatCard(title: "Sessions", value: "\(summary.totalSessions)", unit: nil, icon: "figure.strengthtraining.traditional")
                StatCard(title: "Best set", value: "\(summary.bestSetReps)", unit: "reps", icon: "bolt.fill")
                StatCard(
                    title: "Best day",
                    value: "\(summary.bestDayReps)",
                    unit: summary.bestDayDate.map { $0.formatted(.dateTime.day().month()) },
                    icon: "star.fill"
                )
                StatCard(
                    title: "Longest session",
                    value: Duration.seconds(summary.longestSessionDuration).formatted(.time(pattern: .minuteSecond)),
                    unit: nil,
                    icon: "timer"
                )
                StatCard(
                    title: "Avg pace",
                    value: summary.averageRepInterval.map { String(format: "%.1f", $0) } ?? "–",
                    unit: "s/rep",
                    icon: "metronome.fill"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Card chrome

    private func chartCard(
        title: String,
        icon: String,
        caption: String,
        @ViewBuilder chart: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            chart()
                .frame(height: 200)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    StatsView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
