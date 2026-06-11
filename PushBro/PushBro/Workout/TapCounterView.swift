//
//  TapCounterView.swift
//  PushBro
//

import SwiftUI

/// Active-workout counter for manual mode: the whole screen is the tap target
/// so a nose-tap anywhere registers a rep.
struct TapCounterView: View {
    let engine: WorkoutEngine
    var voiceHint = false
    var heartRate: Double?
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("SET \(engine.setNumber)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.secondary)

            ActivityPhaseView(engine: engine)

            Text("\(engine.currentSetReps)")
                .font(.system(size: 180, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy, value: engine.currentSetReps)

            if engine.setNumber > 1 {
                Text("Total \(engine.totalReps)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let start = engine.sessionStart {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(start, style: .timer)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if let heartRate {
                Label("\(Int(heartRate)) bpm", systemImage: "heart.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(heartRate))
            }

            Button(role: .destructive, action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .padding(.top, 16)

            if voiceHint {
                Label("or say “stop” when you're done", systemImage: "mic.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            engine.recordRep()
        }
    }
}

#Preview {
    TapCounterView(engine: WorkoutEngine(), onStop: {})
}
