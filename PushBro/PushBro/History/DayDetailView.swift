//
//  DayDetailView.swift
//  PushBro
//

import Charts
import SwiftData
import SwiftUI

/// Sessions and their sets for one selected day. Swipe a session to delete it.
struct DayDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let day: Date
    let sessions: [WorkoutSession]

    var body: some View {
        List {
            Section {
                ForEach(sessions, id: \.persistentModelID) { session in
                    DisclosureGroup {
                        SessionTimelineView(session: session)
                            .padding(.vertical, 4)
                            .listRowSeparator(.hidden)
                        if !session.heartRateValues.isEmpty {
                            HeartRateChartView(session: session)
                                .frame(height: 130)
                                .padding(.vertical, 4)
                                .listRowSeparator(.hidden)
                        }
                        setRows(for: session)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startDate, format: .dateTime.hour().minute())
                                    .font(.headline)
                                Text(sessionSubtitle(session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(session.totalReps)")
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                        }
                    }
                }
                .onDelete(perform: deleteSessions)
            } header: {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
            }
        }
    }

    private func setRows(for session: WorkoutSession) -> some View {
        let sets = session.orderedSets
        return ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Set \(set.index + 1)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(set.repCount) reps")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                HStack {
                    Text(setSubtitle(set))
                    Spacer()
                    if index < sets.count - 1 {
                        let rest = sets[index + 1].startDate.timeIntervalSince(set.endDate)
                        Label("\(formatted(rest)) rest", systemImage: "pause.circle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            Log.data.info("Deleting session of \(session.totalReps) reps from \(session.startDate.formatted(.dateTime.day().month().hour().minute()))")
            modelContext.delete(session)
        }
        do {
            try modelContext.save()
        } catch {
            Log.data.error("Failed to save after deleting session(s): \(error.localizedDescription)")
        }
    }

    private func sessionSubtitle(_ session: WorkoutSession) -> String {
        let duration = formatted(session.duration)
        let sets = session.sets.count
        let mode = session.mode == .camera ? "camera" : "tap"
        return "\(sets) \(sets == 1 ? "set" : "sets") · \(duration) · \(mode)"
    }

    private func setSubtitle(_ set: WorkoutSet) -> String {
        var parts = [formatted(set.duration)]
        let intervals = set.repIntervals
        if !intervals.isEmpty {
            let pace = intervals.reduce(0, +) / Double(intervals.count)
            parts.append(String(format: "%.1fs/rep", pace))
        }
        return parts.joined(separator: " · ")
    }

    private func formatted(_ interval: TimeInterval) -> String {
        Duration.seconds(max(0, interval)).formatted(.time(pattern: .minuteSecond))
    }
}

/// Heart rate over the session, with the sets shaded underneath so the
/// effort/recovery rhythm lines up with the workout structure.
struct HeartRateChartView: View {
    let session: WorkoutSession

    var body: some View {
        let points = Array(zip(session.heartRateOffsets, session.heartRateValues))
        Chart {
            ForEach(session.orderedSets, id: \.persistentModelID) { set in
                RectangleMark(
                    xStart: .value("Start", set.startDate.timeIntervalSince(session.startDate)),
                    xEnd: .value("End", max(set.endDate.timeIntervalSince(session.startDate), set.startDate.timeIntervalSince(session.startDate) + 2))
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.0),
                    y: .value("BPM", point.1)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.red)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    }
                }
            }
        }
        .chartYAxisLabel("bpm")
    }
}

/// Gantt-style timeline of one session: blue blocks are sets (always wide
/// enough for their rep count), thin gray connectors are the rests between
/// them, with length proportional to the pause. Scrolls horizontally so any
/// number of sets stays readable.
struct SessionTimelineView: View {
    let session: WorkoutSession

    /// Horizontal points per second of set duration.
    private let scale = 1.4
    /// Labels must always fit, even on near-instant sets.
    private let minSetWidth = 34.0
    private let barHeight = 28.0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                let sets = session.orderedSets
                ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor)
                        .frame(width: max(minSetWidth, set.duration * scale), height: barHeight)
                        .overlay {
                            Text("\(set.repCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.7)
                        }
                    if index < sets.count - 1 {
                        let rest = sets[index + 1].startDate.timeIntervalSince(set.endDate)
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: min(80, max(12, rest * scale * 0.6)), height: 6)
                    }
                }
            }
        }
        .frame(height: barHeight)
    }
}
