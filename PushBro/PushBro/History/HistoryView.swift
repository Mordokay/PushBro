//
//  HistoryView.swift
//  PushBro
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(AppSettings.dailyGoalKey) private var dailyGoal = AppSettings.defaultDailyGoal

    @State private var displayedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    private var dailyTotals: [Date: Int] {
        StatsCalculator.dailyTotals(sessions)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Finish your first session and it will show up here.")
                    )
                } else {
                    VStack(spacing: 0) {
                        monthHeader
                        CalendarHeatmapView(
                            month: displayedMonth,
                            dailyTotals: dailyTotals,
                            goal: dailyGoal,
                            selectedDay: $selectedDay
                        )
                        .padding(.horizontal)

                        Group {
                            if let selectedDay {
                                DayDetailView(day: selectedDay, sessions: sessions(on: selectedDay))
                            } else {
                                ContentUnavailableView(
                                    "Select a day",
                                    systemImage: "hand.tap",
                                    description: Text("Tap a calendar day to see its sessions.")
                                )
                            }
                        }
                        .padding(.top, 10)
                        .mask {
                            VStack(spacing: 0) {
                                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 14)
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 14)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Seed", systemImage: "wand.and.stars") {
                        DebugSeed.populate(context: modelContext)
                    }
                }
            }
            #endif
        }
    }

    private var monthHeader: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") {
                shiftMonth(by: -1)
            }
            .labelStyle(.iconOnly)
            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button("Next month", systemImage: "chevron.right") {
                shiftMonth(by: 1)
            }
            .labelStyle(.iconOnly)
            .disabled(isCurrentMonthDisplayed)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var isCurrentMonthDisplayed: Bool {
        calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
    }

    private func shiftMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = next
            selectedDay = nil
        }
    }

    private func sessions(on day: Date) -> [WorkoutSession] {
        sessions.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
