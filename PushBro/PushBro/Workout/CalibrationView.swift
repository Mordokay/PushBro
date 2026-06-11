//
//  CalibrationView.swift
//  PushBro
//

import SwiftUI

/// Guided capture of the up/down face distances, ending with a live test.
struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.calibrationJSONKey) private var calibrationJSON = ""
    @AppStorage(AppSettings.downThresholdKey) private var downThreshold = AppSettings.defaultDownThreshold

    @State private var controller: CalibrationController?
    @State private var showRangeTooSmall = false
    @State private var showCaptureFailed = false

    var body: some View {
        Group {
            if let controller {
                content(controller: controller)
            } else {
                ContentUnavailableView(
                    "Camera unavailable",
                    systemImage: "camera.fill",
                    description: Text("This device doesn't support face tracking. Use tap mode instead.")
                )
            }
        }
        .navigationTitle("Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if controller == nil, let provider = FaceDistanceProviderFactory.make() {
                let controller = CalibrationController(provider: provider)
                controller.activate()
                self.controller = controller
            }
        }
        .onDisappear {
            controller?.deactivate()
        }
        .alert("Not enough range", isPresented: $showRangeTooSmall) {
            Button("Try again") {}
        } message: {
            Text("Your up and down positions are less than 10 cm apart. Place the phone under your chest and keep your arms fully extended for the up capture.")
        }
        .alert("Couldn't see you", isPresented: $showCaptureFailed) {
            Button("Try again") {}
        } message: {
            Text("The camera never saw you during the measurement. Make sure “Tracking you” shows before the countdown ends, then lower yourself slowly.")
        }
    }

    @ViewBuilder
    private func content(controller: CalibrationController) -> some View {
        VStack(spacing: 24) {
            stepIndicator(controller.step)

            switch controller.step {
            case .intro:
                instructionCard(
                    icon: "iphone.gen3",
                    title: "Place your phone",
                    text: "Put the phone flat on the floor, screen up, directly under your face — your nose should point at it at the bottom of a rep. Get into plank position over it."
                )
                trackingBadge(controller)
                Button("I'm in position") {
                    controller.beginCapture(.up)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.isTracking)

            case .capturingUp, .capturingDown:
                let isUp = controller.step == .capturingUp
                let measuring = controller.captureCountdown == nil
                instructionCard(
                    icon: isUp ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                    title: isUp
                        ? "Hold the UP position"
                        : (measuring ? "Go down now" : "Get ready"),
                    text: isUp
                        ? "Arms fully extended. Hold still…"
                        : (measuring
                            ? "Lower yourself slowly to your deepest point. It's OK if the camera loses your face near the bottom — that's expected."
                            : "Stay up with arms extended. When the countdown ends, lower yourself slowly.")
                )
                if let countdown = controller.captureCountdown {
                    Text("\(countdown)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .contentTransition(.numericText(countsDown: true))
                } else {
                    ProgressView(isUp ? "Measuring…" : "Measuring your descent…")
                }

            case .betweenCaptures:
                instructionCard(
                    icon: "arrow.down.circle.fill",
                    title: "Up position saved",
                    text: "Next, PushBro measures your descent. Tap the button, stay up through the countdown, then lower yourself slowly to your deepest point."
                )
                Button("Measure my descent") {
                    controller.beginCapture(.down)
                }
                .buttonStyle(.borderedProminent)

            case .test:
                instructionCard(
                    icon: "checkmark.seal.fill",
                    title: "Test it",
                    text: "Do a couple of practice reps. The bar should sweep the full range and the counter should tick."
                )
                DepthBarView(depth: controller.currentDepth, downThreshold: downThreshold)
                    .frame(height: 24)
                    .padding(.horizontal)
                Text("\(controller.testRepCount) practice reps")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Button("Save calibration") {
                    save(controller: controller)
                }
                .buttonStyle(.borderedProminent)
                Button("Start over") {
                    controller.restart()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .onChange(of: controller.failedRangeCheck) { _, failed in
            if failed {
                showRangeTooSmall = true
                controller.restart()
            }
        }
        .onChange(of: controller.failedCapture) { _, failed in
            showCaptureFailed = failed != nil
        }
    }

    private func save(controller: CalibrationController) {
        guard let profile = controller.profile else { return }
        calibrationJSON = profile.encodedJSON()
        dismiss()
    }

    private func stepIndicator(_ step: CalibrationController.Step) -> some View {
        Text(stepLabel(step))
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func stepLabel(_ step: CalibrationController.Step) -> String {
        switch step {
        case .intro: "Step 1 of 4 · Position"
        case .capturingUp: "Step 2 of 4 · Up"
        case .betweenCaptures, .capturingDown: "Step 3 of 4 · Down"
        case .test: "Step 4 of 4 · Test"
        }
    }

    private func instructionCard(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3.weight(.bold))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func trackingBadge(_ controller: CalibrationController) -> some View {
        Label(
            controller.isTracking ? "Tracking you" : "Looking for you…",
            systemImage: controller.isTracking ? "checkmark.circle.fill" : "magnifyingglass"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(controller.isTracking ? .green : .secondary)
    }
}

/// Horizontal gauge of normalized depth with the rep threshold marked.
struct DepthBarView: View {
    let depth: Double?
    let downThreshold: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                if let depth {
                    Capsule()
                        .fill(depth >= downThreshold ? Color.green : Color.accentColor)
                        .frame(width: max(8, geometry.size.width * min(1, max(0, depth))))
                        .animation(.linear(duration: 0.05), value: depth)
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 2)
                    .offset(x: geometry.size.width * downThreshold)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CalibrationView()
    }
}
