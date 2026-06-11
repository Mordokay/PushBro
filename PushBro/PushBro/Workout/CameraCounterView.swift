//
//  CameraCounterView.swift
//  PushBro
//

import SwiftUI

/// Active-workout counter for camera mode: no touching needed, the camera
/// counts. Big type because it's read from plank position.
struct CameraCounterView: View {
    let engine: WorkoutEngine
    let controller: CameraWorkoutController
    let downThreshold: Double
    var voiceHint = false
    var heartRate: Double?
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            statusBadge

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

            DepthBarView(depth: controller.currentDepth, downThreshold: downThreshold)
                .frame(height: 20)
                .padding(.horizontal, 32)

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
    }

    private var statusBadge: some View {
        Group {
            if controller.isTracking {
                Label("Tracking", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            } else {
                Label("Not tracking", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}
