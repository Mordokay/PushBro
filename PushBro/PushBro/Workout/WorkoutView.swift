//
//  WorkoutView.swift
//  PushBro
//

import SwiftData
import SwiftUI
import UIKit

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var announcer: SpeechAnnouncer?
    @State private var engine: WorkoutEngine?
    @State private var cameraController: CameraWorkoutController?
    @State private var voiceListener: VoiceCommandListener?
    @State private var showTutorial = false
    @State private var watchConnector: PhoneWatchConnector?
    /// Session waiting for the watch's end-of-workout summary.
    @State private var pendingWatchSession: WorkoutSession?
    /// True while the dashboard (root workout content) is frontmost — false
    /// when another tab is selected or calibration is pushed over it.
    @State private var isDashboardVisible = false

    @AppStorage(AppSettings.startTimerSecondsKey) private var startTimerSeconds = AppSettings.defaultStartTimerSeconds
    @AppStorage(AppSettings.restThresholdKey) private var restThreshold = AppSettings.defaultRestThreshold
    @AppStorage(AppSettings.downThresholdKey) private var downThreshold = AppSettings.defaultDownThreshold
    @AppStorage(AppSettings.spokenCountEnabledKey) private var spokenCountEnabled = true
    @AppStorage(AppSettings.voiceCommandsEnabledKey) private var voiceCommandsEnabled = true
    @AppStorage(AppSettings.calibrationJSONKey) private var calibrationJSON = ""
    @AppStorage(AppSettings.preferredModeKey) private var preferredModeRaw = WorkoutMode.camera.rawValue
    @AppStorage(AppSettings.healthKitEnabledKey) private var healthKitEnabled = false
    @AppStorage(AppSettings.userNameKey) private var userName = ""
    @AppStorage(AppSettings.watchHeartRateEnabledKey) private var watchHeartRateEnabled = true

    private let timerChoices = [3, 5, 10]

    private var selectedMode: WorkoutMode {
        get { WorkoutMode(rawValue: preferredModeRaw) ?? .manual }
    }

    private var calibration: CalibrationProfile? {
        CalibrationProfile.decode(fromJSON: calibrationJSON)
    }

    private var cameraAvailable: Bool {
        FaceDistanceProviderFactory.isCameraModeAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if let engine {
                    content(engine: engine)
                } else {
                    Color.clear
                }
            }
            .onAppear {
                isDashboardVisible = true
                refreshVoiceListening()
            }
            .onDisappear {
                isDashboardVisible = false
                refreshVoiceListening()
            }
            .navigationTitle("PushBro")
            .toolbarVisibility(
                engine?.phase == .active || engine?.phase == .summary ? .hidden : .visible,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("How it works", systemImage: "questionmark.circle") {
                        showTutorial = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showTutorial) {
                TutorialView()
                    .presentationDetents([.large])
            }
            .onChange(of: showTutorial) { _, _ in
                refreshVoiceListening()
            }
        }
        .onAppear {
            if engine == nil {
                let announcer = SpeechAnnouncer()
                self.announcer = announcer
                engine = WorkoutEngine(announcer: announcer)
            }
            setUpVoiceAndInterruptions()
            setUpWatch()
        }
        .onChange(of: engine?.totalReps) { _, newCount in
            if let newCount, newCount > 0 {
                watchConnector?.sendRepCount(newCount)
            }
        }
        .onChange(of: engine?.phase) { _, newPhase in
            let workingOut: Bool = switch newPhase {
            case .countdown, .active: true
            default: false
            }
            UIApplication.shared.isIdleTimerDisabled = workingOut

            // Tear the camera down as soon as the workout ends.
            switch newPhase {
            case .summary, .idle, .none:
                cameraController?.stop()
                cameraController = nil
            default:
                break
            }

            if newPhase == .summary, let session = engine?.finishedSession {
                if watchConnector?.isWatchWorkoutRunning == true {
                    // The watch saves to Health itself; HR and calories
                    // attach when its summary arrives. If it never does
                    // (watch app stalled, never launched), fall back so the
                    // workout still reaches Health.
                    pendingWatchSession = session
                    watchConnector?.stopWatchWorkout()
                    Task {
                        try? await Task.sleep(for: .seconds(15))
                        guard pendingWatchSession === session else { return }
                        Log.workout.warning("Watch summary timed out — saving to Health from the phone")
                        pendingWatchSession = nil
                        if healthKitEnabled {
                            await HealthKitManager.shared.save(session)
                        }
                    }
                } else if healthKitEnabled {
                    Task {
                        await HealthKitManager.shared.save(session)
                    }
                }
            }
            if newPhase == .idle || newPhase == .none {
                watchConnector?.stopWatchWorkout()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            cameraController?.stop()
            cameraController = nil
            voiceListener?.stopListening()
            AudioSessionCoordinator.shared.deactivate()
        }
    }

    /// Voice commands listen only while the dashboard itself is frontmost:
    /// not on other tabs, not under the tutorial sheet, and not while
    /// calibration is pushed (a stray "start" there would launch an
    /// invisible workout).
    private func refreshVoiceListening() {
        guard let voiceListener else { return }
        let shouldListen = voiceCommandsEnabled && isDashboardVisible && !showTutorial && voiceListener.isAuthorized
        if shouldListen {
            if !voiceListener.isListening {
                AudioSessionCoordinator.shared.activate(recording: true)
                voiceListener.startListening()
            }
        } else {
            voiceListener.stopListening()
        }
    }

    private func setUpWatch() {
        guard watchHeartRateEnabled else { return }
        let connector = PhoneWatchConnector.shared
        watchConnector = connector
        connector.onSummary = { summary in
            guard let session = pendingWatchSession else { return }
            let start = session.startDate.timeIntervalSince1970
            let pairs = zip(summary.hrTimes, summary.hrValues).filter { $0.0 >= start }
            session.heartRateOffsets = pairs.map { $0.0 - start }
            session.heartRateValues = pairs.map { $0.1 }
            session.watchEnergyKcal = summary.energyKcal
            if summary.savedToHealth {
                session.healthKitWorkoutID = summary.workoutUUID
            }
            try? modelContext.save()
            if healthKitEnabled, !summary.savedToHealth {
                Task {
                    await HealthKitManager.shared.save(session)
                }
            }
            pendingWatchSession = nil
        }
    }

    /// Voice listening runs whenever this tab is visible so "start" works
    /// hands-free from plank position, and "stop" works mid-workout.
    private func setUpVoiceAndInterruptions() {
        AudioSessionCoordinator.shared.onInterruption = { began in
            guard let engine else { return }
            if began {
                voiceListener?.stopListening()
                if engine.phase == .active {
                    engine.stop(context: modelContext)
                } else {
                    engine.cancelCountdown()
                }
            } else {
                refreshVoiceListening()
            }
        }

        guard voiceCommandsEnabled else {
            voiceListener?.stopListening()
            return
        }
        let listener = voiceListener ?? VoiceCommandListener()
        voiceListener = listener
        listener.announcer = announcer
        listener.onCommand = { command in
            guard let engine else { return }
            switch command {
            case .start:
                if engine.phase == .idle {
                    start(engine: engine)
                }
            case .stop:
                switch engine.phase {
                case .active:
                    engine.stop(context: modelContext)
                case .countdown:
                    engine.cancelCountdown()
                default:
                    break
                }
            }
        }
        Task {
            if await listener.requestAuthorization() {
                refreshVoiceListening()
            }
        }
    }

    @ViewBuilder
    private func content(engine: WorkoutEngine) -> some View {
        switch engine.phase {
        case .idle, .awaitingStart:
            startScreen(engine: engine)
        case .countdown(let remaining):
            countdownScreen(engine: engine, remaining: remaining)
        case .active:
            if let cameraController, engine.mode == .camera {
                CameraCounterView(
                    engine: engine,
                    controller: cameraController,
                    downThreshold: downThreshold,
                    voiceHint: voiceListener?.isListening == true,
                    heartRate: watchConnector?.liveHeartRate
                ) {
                    engine.stop(context: modelContext)
                }
            } else {
                TapCounterView(
                    engine: engine,
                    voiceHint: voiceListener?.isListening == true,
                    heartRate: watchConnector?.liveHeartRate
                ) {
                    engine.stop(context: modelContext)
                }
            }
        case .summary:
            if let session = engine.finishedSession {
                WorkoutSummaryView(session: session) {
                    engine.dismissSummary()
                }
            }
        }
    }

    private func startScreen(engine: WorkoutEngine) -> some View {
        VStack(spacing: 28) {
            Spacer()

            if !userName.isEmpty {
                Text("Ready, \(userName)?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if cameraAvailable {
                Picker("Mode", selection: $preferredModeRaw) {
                    Label("Camera", systemImage: "camera.fill").tag(WorkoutMode.camera.rawValue)
                    Label("Tap", systemImage: "hand.tap.fill").tag(WorkoutMode.manual.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
            }

            modeExplainer

            VStack(spacing: 12) {
                Text("Start delay")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Start delay", selection: $startTimerSeconds) {
                    ForEach(timerChoices, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            if selectedMode == .camera && cameraAvailable && calibration == nil {
                NavigationLink {
                    CalibrationView()
                } label: {
                    Label("Calibrate first", systemImage: "camera.metering.center.weighted")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    start(engine: engine)
                } label: {
                    Label("Start", systemImage: "timer")
                        .font(.title2.weight(.bold))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)

                if voiceListener?.isListening == true {
                    Label("or just say “start”", systemImage: "mic.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
    }

    private var modeExplainer: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedMode == .camera && cameraAvailable ? "camera.viewfinder" : "figure.strengthtraining.traditional")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(selectedMode == .camera && cameraAvailable ? "Camera mode" : "Tap mode")
                .font(.title2.weight(.bold))
            Text(
                selectedMode == .camera && cameraAvailable
                    ? "Place the phone under your face, screen up. The front camera counts your reps."
                    : "Tap the screen with your nose for each rep."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private func start(engine: WorkoutEngine) {
        announcer?.isEnabled = spokenCountEnabled
        engine.restThreshold = restThreshold
        AudioSessionCoordinator.shared.activate(recording: voiceCommandsEnabled && voiceListener?.isAuthorized == true)

        Log.workout.info("Start requested — mode: \(selectedMode.rawValue), delay: \(startTimerSeconds) s, voice: \(voiceListener?.isListening == true), spoken count: \(spokenCountEnabled), watch: \(watchConnector?.isWatchAvailable == true)")

        if watchHeartRateEnabled {
            watchConnector?.startWatchWorkout(saveToHealth: healthKitEnabled)
        }

        if selectedMode == .camera, cameraAvailable, let calibration,
           let provider = FaceDistanceProviderFactory.make() {
            engine.mode = .camera
            let controller = CameraWorkoutController(provider: provider, engine: engine)
            // Start during the countdown so ARKit acquires the face while the
            // user gets into position; the engine ignores reps until active.
            controller.start(config: RepDetectionConfig(
                calibration: calibration,
                downThreshold: downThreshold,
                restThreshold: restThreshold
            ))
            cameraController = controller
        } else {
            engine.mode = .manual
        }

        engine.startCountdown(seconds: startTimerSeconds)
    }

    private func countdownScreen(engine: WorkoutEngine, remaining: Int) -> some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Get into position")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(remaining)")
                .font(.system(size: 180, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: remaining)
            Button("Cancel") {
                engine.cancelCountdown()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }
}

#Preview {
    WorkoutView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
