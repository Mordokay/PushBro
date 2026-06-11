//
//  OnboardingView.swift
//  PushBro
//

import SwiftUI

/// First-launch setup: name, goal, body weight, voice preferences, and
/// Apple Health — every page skippable. Settings can change all of it later.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.userNameKey) private var userName = ""
    @AppStorage(AppSettings.dailyGoalKey) private var dailyGoal = AppSettings.defaultDailyGoal
    @AppStorage(AppSettings.bodyWeightKgKey) private var bodyWeightKg = 0.0
    @AppStorage(AppSettings.voiceCommandsEnabledKey) private var voiceCommandsEnabled = true
    @AppStorage(AppSettings.spokenCountEnabledKey) private var spokenCountEnabled = true
    @AppStorage(AppSettings.healthKitEnabledKey) private var healthKitEnabled = false

    @State private var page = 0
    @State private var weightText = ""
    @State private var usesPounds = Locale.current.measurementSystem != .metric
    @FocusState private var weightFieldFocused: Bool

    private let pageCount = 5

    enum FitnessLevel: String, CaseIterable, Identifiable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"

        var id: String { rawValue }

        var suggestedGoal: Int {
            switch self {
            case .beginner: 20
            case .intermediate: 50
            case .advanced: 100
            }
        }

        var subtitle: String {
            switch self {
            case .beginner: "20 pushups a day to build the habit"
            case .intermediate: "50 a day — the classic"
            case .advanced: "100 a day, no excuses"
            }
        }
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip") {
                    finish()
                }
                .padding()
            }

            TabView(selection: $page) {
                welcomePage.tag(0)
                goalPage.tag(1)
                bodyPage.tag(2)
                voicePage.tag(3)
                healthPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .onChange(of: page) { _, _ in
                weightFieldFocused = false
            }

            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Text(page < pageCount - 1 ? "Next" : "Let's train")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func finish() {
        commitWeight()
        Log.app.info("Onboarding finished (name: \(userName.isEmpty ? "skipped" : "set"), goal: \(dailyGoal), weight: \(bodyWeightKg > 0 ? "set" : "skipped"), health: \(healthKitEnabled))")
        dismiss()
    }

    // MARK: - Pages

    private var welcomePage: some View {
        pageLayout(
            icon: "figure.strengthtraining.traditional",
            title: "Welcome to PushBro",
            text: "Your phone counts your pushups — hands-free. A few quick questions to set you up; everything is optional and changeable later."
        ) {
            TextField("What should we call you?", text: $userName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
                .frame(maxWidth: 280)
        }
    }

    private var goalPage: some View {
        pageLayout(
            icon: "target",
            title: "Pick a daily goal",
            text: "Your streak, calendar, and charts all measure against this."
        ) {
            VStack(spacing: 10) {
                ForEach(FitnessLevel.allCases) { level in
                    Button {
                        dailyGoal = level.suggestedGoal
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.rawValue)
                                    .font(.headline)
                                Text(level.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: dailyGoal == level.suggestedGoal ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(dailyGoal == level.suggestedGoal ? Color.accentColor : Color.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Stepper(value: $dailyGoal, in: 10...500, step: 5) {
                    Text("Custom: \(dailyGoal)/day")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 320)
        }
    }

    private var bodyPage: some View {
        pageLayout(
            icon: "scalemass.fill",
            title: "Your weight (optional)",
            text: "Used only to estimate calories for Apple Health. Skip it and workouts are still saved — just without calories."
        ) {
            HStack {
                TextField(usesPounds ? "Weight in lb" : "Weight in kg", text: $weightText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .focused($weightFieldFocused)
                    .frame(maxWidth: 160)
                Picker("Unit", selection: $usesPounds) {
                    Text("kg").tag(false)
                    Text("lb").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
        .onAppear {
            if bodyWeightKg > 0 {
                let display = usesPounds ? bodyWeightKg / 0.45359237 : bodyWeightKg
                weightText = String(format: "%.0f", display)
            }
        }
        .onChange(of: page) { old, _ in
            if old == 2 { commitWeight() }
        }
    }

    private var voicePage: some View {
        pageLayout(
            icon: "mic.fill",
            title: "Hands-free control",
            text: "Say “start” and “stop” instead of touching the phone, and hear every rep counted aloud."
        ) {
            VStack(spacing: 12) {
                Toggle("Voice start/stop commands", isOn: $voiceCommandsEnabled)
                Toggle("Spoken rep counting", isOn: $spokenCountEnabled)
            }
            .frame(maxWidth: 320)
        }
    }

    private var healthPage: some View {
        pageLayout(
            icon: "heart.fill",
            title: "Apple Health",
            text: "Save every session as a strength workout\(bodyWeightKg > 0 || !weightText.isEmpty ? " with estimated calories" : "") so your rings get credit."
        ) {
            Toggle("Save workouts to Apple Health", isOn: $healthKitEnabled)
                .frame(maxWidth: 320)
                .onChange(of: healthKitEnabled) { _, enabled in
                    guard enabled else { return }
                    Task {
                        if await !HealthKitManager.shared.requestAuthorization() {
                            healthKitEnabled = false
                        }
                    }
                }
        }
    }

    // MARK: - Helpers

    private func commitWeight() {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return }
        bodyWeightKg = usesPounds ? value * 0.45359237 : value
    }

    private func pageLayout(
        icon: String,
        title: String,
        text: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            content()
                .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.bottom, 32)
    }
}

#Preview {
    OnboardingView()
}
