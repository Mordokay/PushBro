//
//  WorkoutEngine.swift
//  PushBro
//

import Foundation
import SwiftData

/// Orchestrates a workout session. Consumes rep events — from screen taps in
/// manual mode or the detection state machine in camera mode — and handles
/// countdown, set splitting by rest gaps, spoken counting, and persistence.
@Observable
final class WorkoutEngine {
    private(set) var phase: WorkoutPhase = .idle
    private(set) var currentSetReps = 0
    private(set) var totalReps = 0
    /// 1-based, for display.
    private(set) var setNumber = 1
    private(set) var sessionStart: Date?
    /// When the most recent rep landed — drives the active/rest indicator.
    private(set) var lastRepAt: Date?
    /// The persisted session shown by the summary screen.
    private(set) var finishedSession: WorkoutSession?

    var mode: WorkoutMode = .manual
    var restThreshold: TimeInterval = AppSettings.defaultRestThreshold

    private weak var announcer: (any Announcing)?

    private struct OpenSet {
        var startDate: Date
        var lastRepDate: Date
        var offsets: [Double]
    }

    private struct ClosedSet {
        var startDate: Date
        var endDate: Date
        var offsets: [Double]
    }

    private var openSet: OpenSet?
    private var closedSets: [ClosedSet] = []
    private var countdownTask: Task<Void, Never>?

    init(announcer: (any Announcing)? = nil) {
        self.announcer = announcer
    }

    // MARK: - Phase control

    func startCountdown(seconds: Int) {
        guard phase == .idle || phase == .awaitingStart else { return }
        Log.workout.info("Countdown started (\(seconds) s, mode: \(mode.rawValue), rest threshold: \(restThreshold) s)")
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                guard let self, !Task.isCancelled else { return }
                phase = .countdown(remaining)
                if remaining <= 3 { announcer?.speak("\(remaining)") }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            begin()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        if case .countdown = phase {
            Log.workout.info("Countdown cancelled")
            phase = .idle
        }
    }

    /// Enters the active phase. Called by the countdown task; exposed for tests.
    func begin(at date: Date = .now) {
        Log.workout.info("Workout active")
        sessionStart = date
        phase = .active
        announcer?.speak("Go")
    }

    // MARK: - Rep input

    /// Records one completed rep. A gap longer than `restThreshold` since the
    /// previous rep closes the current set and opens the next one.
    func recordRep(at date: Date = .now) {
        guard phase == .active else { return }

        if var set = openSet {
            if date.timeIntervalSince(set.lastRepDate) > restThreshold {
                Log.workout.info(String(format: "Rest gap of %.1f s — starting set %d", date.timeIntervalSince(set.lastRepDate), setNumber + 1))
                closeOpenSet()
                openSet = OpenSet(startDate: date, lastRepDate: date, offsets: [0])
                setNumber += 1
                currentSetReps = 0
            } else {
                set.offsets.append(date.timeIntervalSince(set.startDate))
                set.lastRepDate = date
                openSet = set
            }
        } else {
            openSet = OpenSet(startDate: date, lastRepDate: date, offsets: [0])
        }

        currentSetReps += 1
        totalReps += 1
        lastRepAt = date
        announcer?.speak("\(currentSetReps)")
    }

    // MARK: - Finishing

    /// Ends the session and persists it. Zero-rep sessions are discarded.
    func stop(at date: Date = .now, context: ModelContext) {
        countdownTask?.cancel()
        countdownTask = nil
        guard phase == .active else {
            reset()
            return
        }
        closeOpenSet()

        guard totalReps > 0, let sessionStart, let lastSet = closedSets.last else {
            Log.workout.info("Session discarded (0 reps)")
            reset()
            return
        }

        let session = WorkoutSession(
            startDate: sessionStart,
            endDate: lastSet.endDate,
            mode: mode,
            totalReps: totalReps
        )
        session.sets = closedSets.enumerated().map { index, set in
            WorkoutSet(index: index, startDate: set.startDate, endDate: set.endDate, repOffsets: set.offsets)
        }
        context.insert(session)
        do {
            try context.save()
            Log.workout.info("Session saved: \(totalReps) reps in \(closedSets.count) set(s), \(String(format: "%.0f", session.duration)) s, mode \(mode.rawValue)")
        } catch {
            Log.workout.error("Failed to save session: \(error.localizedDescription)")
        }

        finishedSession = session
        phase = .summary
    }

    func dismissSummary() {
        reset()
    }

    func reset() {
        countdownTask?.cancel()
        countdownTask = nil
        phase = .idle
        currentSetReps = 0
        totalReps = 0
        setNumber = 1
        sessionStart = nil
        lastRepAt = nil
        openSet = nil
        closedSets = []
        finishedSession = nil
    }

    private func closeOpenSet() {
        guard let set = openSet else { return }
        closedSets.append(ClosedSet(startDate: set.startDate, endDate: set.lastRepDate, offsets: set.offsets))
        openSet = nil
    }
}
