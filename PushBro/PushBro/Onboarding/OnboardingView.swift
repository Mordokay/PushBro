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
    @AppStorage(AppSettings.watchHeartRateEnabledKey) private var watchHeartRateEnabled = true
    @AppStorage(AppSettings.userSexKey) private var userSexRaw = ""
    @AppStorage(AppSettings.userAgeKey) private var userAge = 0
    @AppStorage(AppSettings.userHeightCmKey) private var userHeightCm = 0.0

    @State private var page = 0
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var heightCmText = ""
    @State private var heightFeetText = ""
    @State private var heightInchesText = ""
    @State private var usesImperial = Locale.current.measurementSystem != .metric
    @FocusState private var focusedField: Field?

    private let pageCount = 5

    private enum Field {
        case name
        case age
        case height
        case heightInches
        case weight
    }

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
            .onChange(of: page) { old, _ in
                focusedField = nil
                if old == 2 {
                    commitBodyInfo()
                }
            }

            Button {
                focusedField = nil
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
        focusedField = nil
        commitBodyInfo()
        Log.app.info("Onboarding finished (name: \(userName.isEmpty ? "skipped" : "set"), goal: \(dailyGoal), sex: \(userSexRaw.isEmpty ? "skipped" : userSexRaw), age: \(userAge > 0 ? "set" : "skipped"), height: \(userHeightCm > 0 ? "set" : "skipped"), weight: \(bodyWeightKg > 0 ? "set" : "skipped"), health: \(healthKitEnabled))")
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
                .focused($focusedField, equals: .name)
                .frame(maxWidth: 280)
        }
    }

    private var goalPage: some View {
        pageLayout(
            icon: "target",
            title: "Pick a daily goal",
            text: "Your streak, calendar, and charts all measure against this."
        ) {
            EmptyView()
                .onChange(of: dailyGoal) { old, new in
                    GoalHistoryStore.recordChange(from: old, to: new)
                }
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
            icon: "person.text.rectangle.fill",
            title: "About you",
            text: "All optional — used only to improve the calorie estimates saved to Apple Health."
        ) {
            VStack(spacing: 14) {
                Picker("Sex", selection: $userSexRaw) {
                    ForEach(Sex.allCases) { sex in
                        Text(sex.label).tag(sex.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Units", selection: $usesImperial) {
                    Text("Metric").tag(false)
                    Text("Imperial").tag(true)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Age", text: $ageText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .age)
                        .frame(maxWidth: 100)
                    Text("years")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    if usesImperial {
                        TextField("Height", text: $heightFeetText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .height)
                            .frame(maxWidth: 70)
                        Text("ft")
                            .foregroundStyle(.secondary)
                        TextField("", text: $heightInchesText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .heightInches)
                            .frame(maxWidth: 60)
                        Text("in")
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("Height", text: $heightCmText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .height)
                            .frame(maxWidth: 100)
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    TextField("Weight", text: $weightText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                        .frame(maxWidth: 100)
                    Text(usesImperial ? "lb" : "kg")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: 280)
        }
        .onAppear {
            if bodyWeightKg > 0 {
                let display = usesImperial ? bodyWeightKg / 0.45359237 : bodyWeightKg
                weightText = String(format: "%.0f", display)
            }
            if userAge > 0 {
                ageText = "\(userAge)"
            }
            if userHeightCm > 0 {
                if usesImperial {
                    let totalInches = userHeightCm / 2.54
                    heightFeetText = "\(Int(totalInches / 12))"
                    heightInchesText = "\(Int(totalInches.truncatingRemainder(dividingBy: 12).rounded()))"
                } else {
                    heightCmText = String(format: "%.0f", userHeightCm)
                }
            }
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
            VStack(spacing: 12) {
                Toggle("Save workouts to Apple Health", isOn: $healthKitEnabled)
                    .onChange(of: healthKitEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            if await !HealthKitManager.shared.requestAuthorization() {
                                healthKitEnabled = false
                            }
                        }
                    }
                Toggle("Apple Watch heart rate", isOn: $watchHeartRateEnabled)
                Text("With a paired watch, workouts track live heart rate for the most accurate calories — and a heart rate graph on every session.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
        }
    }

    // MARK: - Helpers

    private func commitBodyInfo() {
        if let value = Double(weightText.replacingOccurrences(of: ",", with: ".")), value > 0 {
            bodyWeightKg = usesImperial ? value * 0.45359237 : value
        }
        if let value = Int(ageText), (5...120).contains(value) {
            userAge = value
        }
        let heightCm: Double? = if usesImperial {
            Double(heightFeetText).map { feet in
                (feet * 12 + (Double(heightInchesText) ?? 0)) * 2.54
            }
        } else {
            Double(heightCmText.replacingOccurrences(of: ",", with: "."))
        }
        if let heightCm, (100...250).contains(heightCm) {
            userHeightCm = heightCm
        }
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
