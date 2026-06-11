//
//  ActivityPhaseView.swift
//  PushBro
//

import SwiftUI

/// Live active/rest indicator for the workout screens: green "Active" while
/// reps are flowing, and once the rest threshold passes without a rep, an
/// orange count-up timer of the current rest.
struct ActivityPhaseView: View {
    let engine: WorkoutEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Group {
                if let lastRep = engine.lastRepAt {
                    let sinceLastRep = context.date.timeIntervalSince(lastRep)
                    if sinceLastRep > engine.restThreshold {
                        Label {
                            Text("Rest \(Duration.seconds(sinceLastRep).formatted(.time(pattern: .minuteSecond)))")
                        } icon: {
                            Image(systemName: "pause.circle.fill")
                        }
                        .foregroundStyle(.orange)
                    } else {
                        Label("Active", systemImage: "bolt.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Label("Waiting for your first rep", systemImage: "figure.strengthtraining.traditional")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
    }
}
