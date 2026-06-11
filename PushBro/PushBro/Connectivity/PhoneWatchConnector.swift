//
//  PhoneWatchConnector.swift
//  PushBro
//

import Foundation
import WatchConnectivity

/// iPhone side of the watch link: commands out (start/stop/rep counts),
/// live heart rate and the end-of-workout summary in.
@Observable
@MainActor
final class PhoneWatchConnector: NSObject {
    /// WCSession allows a single delegate, so one shared instance.
    static let shared = PhoneWatchConnector()

    struct WatchWorkoutSummary {
        /// Epoch seconds + bpm, parallel arrays.
        var hrTimes: [Double]
        var hrValues: [Double]
        /// Watch-computed active energy.
        var energyKcal: Double?
        /// True when the watch already saved the workout to Health.
        var savedToHealth: Bool
        var workoutUUID: UUID?
    }

    private(set) var isWatchAvailable = false
    private(set) var liveHeartRate: Double?
    private(set) var isWatchWorkoutRunning = false

    var onSummary: ((WatchWorkoutSummary) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Forces early activation so availability is known before the first workout.
    func warmUp() {}

    /// `saveToHealth` carries the phone's Apple Health setting to the watch —
    /// the watch's builder is what actually saves the workout.
    func startWatchWorkout(saveToHealth: Bool) {
        guard isWatchAvailable else { return }
        isWatchWorkoutRunning = true
        liveHeartRate = nil
        // Three delivery paths because each can individually fail: launching
        // via HealthKit wakes the app, applicationContext is guaranteed to
        // reach it once running, and the direct message covers the
        // already-reachable case immediately.
        HealthKitManager.shared.launchWatchApp()
        publishDesiredState(active: true, saveToHealth: saveToHealth)
        send(["command": "start", "saveToHealth": saveToHealth])
        Log.workout.info("Watch workout requested (save to Health: \(saveToHealth))")
    }

    func stopWatchWorkout() {
        guard isWatchWorkoutRunning else { return }
        isWatchWorkoutRunning = false
        publishDesiredState(active: false, saveToHealth: false)
        send(["command": "stop"])
        Log.workout.info("Watch workout stop requested")
    }

    /// applicationContext is latest-wins and survives unreachability — the
    /// watch reconciles against it at activation and on every update.
    private func publishDesiredState(active: Bool, saveToHealth: Bool) {
        guard WCSession.default.activationState == .activated else { return }
        do {
            try WCSession.default.updateApplicationContext([
                "workoutActive": active,
                "saveToHealth": saveToHealth,
                "ts": Date().timeIntervalSince1970,
            ])
        } catch {
            Log.workout.warning("updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    func sendRepCount(_ count: Int) {
        guard isWatchWorkoutRunning else { return }
        send(["command": "rep", "count": count])
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                Log.workout.warning("Watch message failed: \(error.localizedDescription)")
            }
        } else {
            Log.workout.debug("Watch unreachable — skipped \(message["command"] as? String ?? "?") message")
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "watchLog":
            Log.watch.info("⌚️ \(message["message"] as? String ?? "?")")
        case "hr":
            liveHeartRate = message["bpm"] as? Double
        case "summary":
            isWatchWorkoutRunning = false
            liveHeartRate = nil
            let summary = WatchWorkoutSummary(
                hrTimes: message["hrTimes"] as? [Double] ?? [],
                hrValues: message["hrValues"] as? [Double] ?? [],
                energyKcal: (message["energy"] as? Double).flatMap { $0 > 0 ? $0 : nil },
                savedToHealth: message["saved"] as? Bool ?? false,
                workoutUUID: (message["uuid"] as? String).flatMap(UUID.init)
            )
            Log.workout.info("Watch summary received: \(summary.hrValues.count) HR samples, \(summary.energyKcal.map { String(format: "%.0f kcal", $0) } ?? "no energy"), saved: \(summary.savedToHealth)")
            onSummary?(summary)
        case "watchError":
            isWatchWorkoutRunning = false
            Log.workout.error("Watch workout error: \(message["message"] as? String ?? "unknown")")
        default:
            break
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneWatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let available = activationState == .activated && session.isPaired && session.isWatchAppInstalled
        Task { @MainActor in
            self.isWatchAvailable = available
            Log.workout.info("Watch connectivity: \(available ? "available" : "unavailable") (paired: \(session.isPaired), app installed: \(session.isWatchAppInstalled))")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let available = session.isPaired && session.isWatchAppInstalled
        Task { @MainActor in
            self.isWatchAvailable = available
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            Log.workout.info("Watch reachability changed: \(reachable ? "reachable" : "unreachable")")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handle(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Fallback transport for summaries when reachability lapsed.
        Task { @MainActor in
            self.handle(userInfo)
        }
    }
}
