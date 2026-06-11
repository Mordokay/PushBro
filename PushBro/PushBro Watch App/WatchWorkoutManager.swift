//
//  WatchWorkoutManager.swift
//  PushBro Watch App
//

import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// Runs the HKWorkoutSession that keeps the watch app alive and the heart
/// sensor in continuous mode, and relays live data to the iPhone.
///
/// The watch's HKLiveWorkoutBuilder saves the workout to Health itself (with
/// real heart rate and sensor-fused calories), so the phone skips its own
/// Health save when a watch session ran.
@Observable
@MainActor
final class WatchWorkoutManager: NSObject {
    static let shared = WatchWorkoutManager()

    private(set) var isWorkoutActive = false
    /// True when the user denied heart-rate sharing on the consent sheet —
    /// iOS won't re-prompt, so the UI must point at Settings.
    private(set) var heartRateAccessDenied = false
    private(set) var heartRate: Double = 0
    private(set) var activeEnergy: Double = 0
    private(set) var repCount = 0
    private(set) var startDate: Date?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Epoch seconds + bpm, sent to the phone with the final summary.
    private var hrTimes: [Double] = []
    private var hrValues: [Double] = []
    private var sentFirstHeartRate = false
    private var hasRequestedAuthorization = false
    /// Mirrors the phone's "Save workouts to Apple Health" setting.
    private var shouldSaveToHealth = true
    /// Set synchronously the moment a start is accepted — the async session
    /// setup leaves a window where a second start path (launch handler,
    /// direct message, applicationContext) could otherwise create a duplicate
    /// HKWorkoutSession and orphan the first.
    private var isStarting = false

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        relay("Watch app started (v\(version) build \(build)), WCSession activating")
    }

    /// Logs locally (same emoji format as the iOS app) and queues the event
    /// to the phone console. transferUserInfo survives unreachability.
    private func relay(_ message: String) {
        Log.watch.info(message)
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(["type": "watchLog", "message": message])
    }

    /// Requesting HealthKit authorization needs a foreground app to present
    /// the consent sheet — a background startWatchApp launch can't. Pre-flight
    /// it whenever the app is opened so background starts never stall on it.
    func requestAuthorizationIfNeeded() {
        // Refresh the denied flag on every foreground visit, so flipping the
        // toggle in Settings clears the warning.
        heartRateAccessDenied = healthStore.authorizationStatus(for: HKQuantityType(.heartRate)) == .sharingDenied
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        Task {
            do {
                try await healthStore.requestAuthorization(
                    toShare: [.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)],
                    read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
                )
                relay("HealthKit authorization pre-flight completed")
                heartRateAccessDenied = healthStore.authorizationStatus(for: HKQuantityType(.heartRate)) == .sharingDenied
            } catch {
                relay("HealthKit authorization pre-flight failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Session lifecycle

    /// Entry point for HKHealthStore.startWatchApp launches.
    func handleLaunchConfiguration() {
        relay("Launched via startWatchApp with workout configuration")
        startWorkout()
    }

    func startWorkout() {
        guard !isWorkoutActive, !isStarting else {
            relay("Start ignored — workout already \(isWorkoutActive ? "active" : "starting")")
            return
        }
        isStarting = true
        relay("Start requested")
        Task {
            await beginSession()
        }
    }

    private func beginSession() async {
        do {
            relay("Requesting HealthKit authorization")
            try await healthStore.requestAuthorization(
                toShare: [.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)],
                read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            )
            relay("HealthKit authorization flow completed")

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .functionalStrengthTraining
            configuration.locationType = .indoor

            relayAuthorizationStatuses()

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            builder.dataSource = dataSource
            builder.delegate = self
            let collectsHR = dataSource.typesToCollect.contains(HKQuantityType(.heartRate))
            let collectsEnergy = dataSource.typesToCollect.contains(HKQuantityType(.activeEnergyBurned))
            relay("Data source will collect: HR \(collectsHR ? "yes" : "NO"), energy \(collectsEnergy ? "yes" : "NO")")

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            self.session = session
            self.builder = builder
            self.startDate = start
            self.heartRate = 0
            self.activeEnergy = 0
            self.repCount = 0
            self.hrTimes = []
            self.hrValues = []
            self.sentFirstHeartRate = false
            self.isWorkoutActive = true
            self.isStarting = false
            WKInterfaceDevice.current().play(.start)
            relay("Workout session running — collecting heart rate")

            // Pushup wrist position can starve the optical sensor; make the
            // silence visible instead of mysterious.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, self.isWorkoutActive, self.hrValues.isEmpty else { return }
                self.relay("No heart rate after 12 s — watch may be loose or wrist flexed")
            }
        } catch {
            isStarting = false
            relay("Workout start FAILED: \(error.localizedDescription)")
            sendToPhone(["type": "watchError", "message": error.localizedDescription])
        }
    }

    func stopWorkout() {
        guard isWorkoutActive, let session, let builder else {
            relay("Stop requested but no active workout")
            return
        }
        relay("Stop requested — ending session (\(hrValues.count) HR samples collected)")
        isWorkoutActive = false
        WKInterfaceDevice.current().play(.stop)
        session.end()
        Task {
            var summary: [String: Any] = [
                "type": "summary",
                "hrTimes": hrTimes,
                "hrValues": hrValues,
                "energy": activeEnergy,
                "saved": false,
            ]
            do {
                try await builder.endCollection(at: Date())
                // A cancelled countdown or zero-rep session isn't a workout.
                let isEmptyWorkout = repCount == 0 && hrValues.count <= 2
                if shouldSaveToHealth, !isEmptyWorkout {
                    let workout = try await builder.finishWorkout()
                    summary["saved"] = true
                    if let uuid = workout?.uuid.uuidString {
                        summary["uuid"] = uuid
                    }
                    relay("Workout saved to Health (\(String(format: "%.0f", activeEnergy)) kcal)")
                } else {
                    builder.discardWorkout()
                    relay("Workout discarded — \(isEmptyWorkout ? "empty session" : "Apple Health saving is disabled on the phone")")
                }
            } catch {
                summary["error"] = error.localizedDescription
                relay("Finishing workout FAILED: \(error.localizedDescription)")
            }
            sendToPhone(summary)
            self.session = nil
            self.builder = nil
            self.startDate = nil
        }
    }

    /// Sharing statuses are inspectable (read statuses are hidden by iOS
    /// design); a denied share toggle almost always means read was denied on
    /// the same consent sheet. Also probes whether any recent HR samples are
    /// readable at all — distinguishes app authorization from sensor issues.
    private func relayAuthorizationStatuses() {
        func describe(_ status: HKAuthorizationStatus) -> String {
            switch status {
            case .sharingAuthorized: "authorized"
            case .sharingDenied: "DENIED"
            case .notDetermined: "not determined"
            @unknown default: "unknown"
            }
        }
        let heartRateStatus = healthStore.authorizationStatus(for: HKQuantityType(.heartRate))
        heartRateAccessDenied = heartRateStatus == .sharingDenied
        let workout = describe(healthStore.authorizationStatus(for: .workoutType()))
        let heartRate = describe(heartRateStatus)
        let energy = describe(healthStore.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)))
        relay("Share authorization — workout: \(workout), HR: \(heartRate), energy: \(energy)")
        if heartRateAccessDenied {
            relay("Heart rate access DENIED — user must enable it: Watch Settings → Privacy & Security → Health → PushBro")
        }

        // Any HR sample in the last 2 h proves the sensor + read access work.
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-7200), end: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: HKQuantityType(.heartRate), predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
            Task { @MainActor in
                if let error {
                    self.relay("HR history probe failed: \(error.localizedDescription)")
                } else if let sample = samples?.first as? HKQuantitySample {
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    self.relay("HR history probe: last sample \(Int(bpm)) bpm at \(sample.endDate.formatted(date: .omitted, time: .standard))")
                } else {
                    self.relay("HR history probe: NO readable samples in last 2 h (read denied, sensor off, or wrist detection disabled)")
                }
            }
        }
        healthStore.execute(query)
    }

    /// The phone publishes desired state through applicationContext, which is
    /// always deliverable; reconcile whenever it changes (or at activation).
    private func reconcile(context: [String: Any]) {
        guard let shouldBeActive = context["workoutActive"] as? Bool else { return }
        if shouldBeActive, !isWorkoutActive {
            if let save = context["saveToHealth"] as? Bool {
                shouldSaveToHealth = save
            }
            relay("ApplicationContext says active — starting workout")
            startWorkout()
        } else if !shouldBeActive, isWorkoutActive {
            relay("ApplicationContext says inactive — stopping workout")
            stopWorkout()
        }
    }

    // MARK: - Data handling

    private func record(heartRate bpm: Double, energy: Double?) {
        heartRate = bpm
        hrTimes.append(Date().timeIntervalSince1970)
        hrValues.append(bpm)
        if let energy {
            activeEnergy = energy
        }
        if !sentFirstHeartRate {
            sentFirstHeartRate = true
            relay("First heart rate sample: \(Int(bpm)) bpm")
        }
        sendToPhone(["type": "hr", "bpm": bpm, "energy": activeEnergy])
    }

    private func sendToPhone(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else if message["type"] as? String == "summary" {
            // Summaries must arrive even if reachability lapsed.
            WCSession.default.transferUserInfo(message)
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        func name(_ state: HKWorkoutSessionState) -> String {
            switch state {
            case .notStarted: "notStarted"
            case .prepared: "prepared"
            case .running: "running"
            case .paused: "paused"
            case .stopped: "stopped"
            case .ended: "ended"
            @unknown default: "unknown(\(state.rawValue))"
            }
        }
        let description = "Session state: \(name(fromState)) → \(name(toState))"
        Task { @MainActor in
            self.relay(description)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.relay("Session FAILED: \(message)")
            self.sendToPhone(["type": "watchError", "message": message])
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var bpm: Double?
        var energy: Double?
        if collectedTypes.contains(HKQuantityType(.heartRate)) {
            bpm = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
                .mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if collectedTypes.contains(HKQuantityType(.activeEnergyBurned)) {
            energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
        }
        guard bpm != nil || energy != nil else { return }
        Task { @MainActor in
            if let bpm {
                self.record(heartRate: bpm, energy: energy)
            } else if let energy {
                self.activeEnergy = energy
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - WCSessionDelegate

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let stateDescription = "\(activationState.rawValue)" + (error.map { ", error: \($0.localizedDescription)" } ?? "")
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.relay("WCSession activated (state \(stateDescription))")
            // The phone may have published the start before we launched.
            self.reconcile(context: context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.reconcile(context: applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            switch message["command"] as? String {
            case "start":
                if let save = message["saveToHealth"] as? Bool {
                    self.shouldSaveToHealth = save
                }
                self.startWorkout()
            case "stop":
                self.stopWorkout()
            case "rep":
                self.repCount = message["count"] as? Int ?? self.repCount
            default:
                break
            }
        }
    }
}
