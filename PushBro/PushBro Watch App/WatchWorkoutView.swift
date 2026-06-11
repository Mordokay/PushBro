//
//  WatchWorkoutView.swift
//  PushBro Watch App
//

import SwiftUI

struct WatchWorkoutView: View {
    @Environment(WatchWorkoutManager.self) private var manager

    var body: some View {
        if manager.isWorkoutActive {
            activeView
        } else {
            idleView
        }
    }

    private var idleView: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("PushBro")
                .font(.headline)
            if manager.heartRateAccessDenied {
                Label("Heart rate access is off. Enable it in Settings → Privacy & Security → Health → PushBro.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
            } else {
                Text("Start a workout on your iPhone — heart rate tracking begins automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onAppear {
            // Get the Health consent sheet out of the way while the app is
            // foreground — background launches can't present it.
            manager.requestAuthorizationIfNeeded()
        }
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            // Top half: heart rate, as big as it fits.
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: manager.heartRate > 0)
                    Text(manager.heartRate > 0 ? "\(Int(manager.heartRate))" : "––")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(manager.heartRate))
                }
                Text("BPM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Bottom half: reps, with elapsed time and energy tucked below.
            VStack(spacing: 0) {
                Text("\(manager.repCount)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: manager.repCount)
                HStack(spacing: 10) {
                    Text("reps")
                    if let start = manager.startDate {
                        Text(start, style: .timer)
                            .monospacedDigit()
                    }
                    Text("\(Int(manager.activeEnergy)) kcal")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    WatchWorkoutView()
        .environment(WatchWorkoutManager.shared)
}
