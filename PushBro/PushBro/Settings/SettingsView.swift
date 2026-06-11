//
//  SettingsView.swift
//  PushBro
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.dailyGoalKey) private var dailyGoal = AppSettings.defaultDailyGoal
    @AppStorage(AppSettings.downThresholdKey) private var downThreshold = AppSettings.defaultDownThreshold
    @AppStorage(AppSettings.restThresholdKey) private var restThreshold = AppSettings.defaultRestThreshold
    @AppStorage(AppSettings.voiceCommandsEnabledKey) private var voiceCommandsEnabled = true
    @AppStorage(AppSettings.spokenCountEnabledKey) private var spokenCountEnabled = true
    @AppStorage(AppSettings.healthKitEnabledKey) private var healthKitEnabled = false
    @AppStorage(AppSettings.calibrationJSONKey) private var calibrationJSON = ""
    @AppStorage(AppSettings.userNameKey) private var userName = ""
    @AppStorage(AppSettings.bodyWeightKgKey) private var bodyWeightKg = 0.0

    @State private var showTutorial = false
    @State private var showResetConfirmation = false
    @State private var isDeletingData = false
    @State private var toast: Toast?

    private var calibration: CalibrationProfile? {
        CalibrationProfile.decode(fromJSON: calibrationJSON)
    }

    private func confirmDeleteAllWorkoutData() {
        isDeletingData = true
        Task {
            let started = ContinuousClock.now
            let success = deleteAllWorkoutData()
            // Keep the overlay visible long enough to read, even when the
            // batch delete is near-instant.
            let elapsed = started.duration(to: .now)
            if elapsed < .milliseconds(800) {
                try? await Task.sleep(for: .milliseconds(800) - elapsed)
            }
            isDeletingData = false
            toast = Toast(
                text: success ? "All workout data deleted" : "Deletion failed",
                isSuccess: success
            )
        }
    }

    private func deleteAllWorkoutData() -> Bool {
        do {
            let sessionCount = try modelContext.fetchCount(FetchDescriptor<WorkoutSession>())
            // Batch deletes skip per-object cascade faulting (the cause of a
            // multi-second freeze with weeks of data), so remove both models.
            try modelContext.delete(model: WorkoutSet.self)
            try modelContext.delete(model: WorkoutSession.self)
            try modelContext.save()
            Log.data.info("All workout data deleted (\(sessionCount) sessions)")
            return true
        } catch {
            Log.data.error("Deleting all workout data failed: \(error.localizedDescription)")
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("Optional", text: $userName)
                            .multilineTextAlignment(.trailing)
                            .textContentType(.givenName)
                    }
                    LabeledContent("Weight") {
                        TextField("Optional", value: $bodyWeightKg, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 80)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Weight is only used to estimate calories for Apple Health.")
                }

                Section("Daily goal") {
                    Stepper(value: $dailyGoal, in: 10...500, step: 5) {
                        HStack {
                            Text("Pushups per day")
                            Spacer()
                            Text("\(dailyGoal)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Rep depth")
                            Spacer()
                            Text("\(Difficulty.nearest(toDownThreshold: downThreshold).label) · \(Int(downThreshold * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $downThreshold, in: 0.5...0.9, step: 0.05) {
                            Text("Rep depth")
                        } minimumValueLabel: {
                            Text("Easy").font(.caption2)
                        } maximumValueLabel: {
                            Text("Hard").font(.caption2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Rest splits a set after")
                            Spacer()
                            Text(String(format: "%.0fs", restThreshold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $restThreshold, in: 2...15, step: 1) {
                            Text("Rest threshold")
                        }
                    }
                } header: {
                    Text("Detection")
                } footer: {
                    Text("Rep depth is how far down you must go, as a fraction of your calibrated range, for a rep to count.")
                }

                Section("Voice") {
                    Toggle("Voice start/stop commands", isOn: $voiceCommandsEnabled)
                    Toggle("Spoken rep counting", isOn: $spokenCountEnabled)
                }

                Section {
                    if let calibration {
                        LabeledContent("Calibrated") {
                            Text(calibration.createdAt, format: .dateTime.day().month().year())
                        }
                        LabeledContent("Range") {
                            Text(String(format: "%.0f cm", calibration.range * 100))
                        }
                    } else {
                        LabeledContent("Calibrated", value: "Not yet")
                    }
                    NavigationLink("Recalibrate") {
                        CalibrationView()
                    }
                } header: {
                    Text("Camera calibration")
                } footer: {
                    Text("Calibration records your up and down face distances so the camera can count reps.")
                }

                Section {
                    Toggle("Save workouts to Apple Health", isOn: $healthKitEnabled)
                        .onChange(of: healthKitEnabled) { _, enabled in
                            guard enabled else { return }
                            Task {
                                if await !HealthKitManager.shared.requestAuthorization() {
                                    healthKitEnabled = false
                                }
                            }
                        }
                }

                Section {
                    Button("How PushBro works") {
                        showTutorial = true
                    }
                }

                Section {
                    Button("Delete all workout data", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .confirmationDialog(
                        "Delete all workout data?",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete everything", role: .destructive) {
                            confirmDeleteAllWorkoutData()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently deletes all sessions, sets, and history. It cannot be undone.")
                    }
                } footer: {
                    Text("Removes every session and set. Settings and calibration are kept.")
                }
            }
            .navigationTitle("Settings")
            .toast($toast)
            .fullScreenCover(isPresented: $isDeletingData) {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Deleting workout data…")
                        .font(.headline)
                }
                .padding(32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationBackground(Color.black.opacity(0.35))
                .interactiveDismissDisabled()
            }
            .onAppear {
                // Values stored before the slider max dropped from 95% to 90%.
                if downThreshold > 0.9 {
                    downThreshold = 0.9
                }
            }
            .sheet(isPresented: $showTutorial) {
                TutorialView()
                    .presentationDetents([.large])
            }
        }
    }
}

#Preview {
    SettingsView()
}
