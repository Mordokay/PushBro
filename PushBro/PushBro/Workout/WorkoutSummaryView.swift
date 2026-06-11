//
//  WorkoutSummaryView.swift
//  PushBro
//

import SwiftData
import SwiftUI

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("\(session.totalReps)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("pushups")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            List {
                Section {
                    ForEach(session.orderedSets, id: \.persistentModelID) { set in
                        HStack {
                            Text("Set \(set.index + 1)")
                                .font(.headline)
                            Spacer()
                            if let pace = averagePace(of: set) {
                                Text(String(format: "%.1fs/rep", pace))
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline.monospacedDigit())
                            }
                            Text("\(set.repCount) reps")
                                .font(.body.monospacedDigit())
                        }
                    }
                } footer: {
                    Text("Duration \(durationText)")
                }
            }

            Button(action: onDone) {
                Text("Done")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var durationText: String {
        Duration.seconds(session.duration).formatted(.time(pattern: .minuteSecond))
    }

    private func averagePace(of set: WorkoutSet) -> Double? {
        let intervals = set.repIntervals
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }
}
