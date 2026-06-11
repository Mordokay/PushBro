//
//  CalendarHeatmapView.swift
//  PushBro
//

import SwiftUI

/// One month of day cells colored by rep total relative to the daily goal.
struct CalendarHeatmapView: View {
    /// First day of the displayed month.
    let month: Date
    /// Reps per start-of-day.
    let dailyTotals: [Date: Int]
    let goal: Int
    @Binding var selectedDay: Date?

    private var calendar: Calendar { .current }

    var body: some View {
        let days = monthGrid()
        VStack(spacing: 8) {
            HStack {
                // Weekday letters repeat ("S", "T"), so identify by position.
                ForEach(Array(weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let total = dailyTotals[day] ?? 0
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date()

        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.footnote.weight(isToday ? .black : .medium))
                if total > 0 {
                    Text("\(total)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(cellColor(total: total), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .opacity(isFuture ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private func cellColor(total: Int) -> Color {
        guard total > 0, goal > 0 else { return Color(.tertiarySystemFill) }
        let fraction = min(1.0, Double(total) / Double(goal))
        return Color.accentColor.opacity(0.25 + 0.75 * fraction)
    }

    /// Cells for a weekday-aligned month grid; nil = leading/trailing blank.
    private func monthGrid() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return cells
    }

    private func weekdaySymbols() -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

#Preview {
    @Previewable @State var selected: Date? = nil
    let today = Calendar.current.startOfDay(for: .now)
    CalendarHeatmapView(
        month: today,
        dailyTotals: [
            today: 55,
            Calendar.current.date(byAdding: .day, value: -1, to: today)!: 30,
            Calendar.current.date(byAdding: .day, value: -3, to: today)!: 80,
        ],
        goal: 50,
        selectedDay: $selected
    )
    .padding()
}
