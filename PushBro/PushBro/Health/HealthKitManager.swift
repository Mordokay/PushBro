//
//  HealthKitManager.swift
//  PushBro
//

import Foundation
import HealthKit

@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()

    private init() {}

    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else {
            Log.health.warning("HealthKit not available on this device")
            return false
        }
        do {
            try await store.requestAuthorization(
                toShare: [.workoutType(), HKQuantityType(.activeEnergyBurned)],
                read: []
            )
            Log.health.info("HealthKit authorization request completed")
            return true
        } catch {
            Log.health.error("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Saves a finished session as an indoor functional-strength workout and
    /// records the resulting UUID on the session. Failures are non-fatal —
    /// the session is already persisted locally.
    func save(_ session: WorkoutSession) async {
        guard Self.isAvailable, session.healthKitWorkoutID == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        // HealthKit rejects zero-duration workouts; a single-rep session can
        // start and end on the same timestamp.
        let endDate = max(session.endDate, session.startDate.addingTimeInterval(1))
        do {
            try await builder.beginCollection(at: session.startDate)
            try await builder.addMetadata([
                HKMetadataKeyWorkoutBrandName: "PushBro",
                "PushBroTotalReps": session.totalReps,
            ])

            // With a known body weight, estimate calories from active set
            // time (rests excluded) so Health rings get credit.
            let defaults = UserDefaults.standard
            let weightKg = defaults.double(forKey: AppSettings.bodyWeightKgKey)
            let age = defaults.integer(forKey: AppSettings.userAgeKey)
            let heightCm = defaults.double(forKey: AppSettings.userHeightCmKey)
            let sex = Sex(rawValue: defaults.string(forKey: AppSettings.userSexKey) ?? "")
            let activeSeconds = session.sets.reduce(0.0) { $0 + $1.duration }
            if let kilocalories = Self.estimatedKilocalories(
                weightKg: weightKg,
                activeSeconds: activeSeconds,
                ageYears: age > 0 ? age : nil,
                sex: sex,
                heightCm: heightCm > 0 ? heightCm : nil
            ) {
                let sample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                    start: session.startDate,
                    end: endDate
                )
                try await builder.addSamples([sample])
                Log.health.debug(String(format: "Estimated %.1f kcal for %.0f s of active sets", kilocalories, activeSeconds))
            }

            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            session.healthKitWorkoutID = workout?.uuid
            Log.health.info("Workout saved to Health (\(session.totalReps) reps, uuid: \(workout?.uuid.uuidString ?? "none"))")
        } catch {
            // Authorization denied or store error; keep the local session.
            Log.health.error("Saving workout to Health failed: \(error.localizedDescription)")
        }
    }

    /// Vigorous calisthenics is ~8 METs.
    private nonisolated static let pushupMETs = 8.0

    /// Energy estimate for the active (set) time of a session.
    ///
    /// With age available, uses the Kozey-corrected MET method: the
    /// individual's resting metabolic rate from Mifflin-St Jeor
    /// (weight/height/age/sex) scaled by the activity's MET multiple —
    /// substantially more accurate across ages and sexes than the textbook
    /// 1 kcal/kg/h assumption. Falls back to the classic MET formula when
    /// only weight is known, and to a sex-typical height when height is
    /// missing. Nil when weight is unknown or there was no active time.
    nonisolated static func estimatedKilocalories(
        weightKg: Double,
        activeSeconds: Double,
        ageYears: Int? = nil,
        sex: Sex? = nil,
        heightCm: Double? = nil
    ) -> Double? {
        guard weightKg > 0, activeSeconds > 0 else { return nil }
        let hours = activeSeconds / 3600

        guard let ageYears, ageYears > 0 else {
            // Classic compendium formula: assumes resting rate of 1 kcal/kg/h.
            return pushupMETs * weightKg * hours
        }

        let height = heightCm ?? typicalHeightCm(for: sex)
        let sexConstant: Double = switch sex {
        case .male: 5
        case .female: -161
        case .other, nil: -78 // midpoint of the sex constants
        }
        // Mifflin-St Jeor resting metabolic rate, kcal/day.
        let rmrPerDay = max(500, 10 * weightKg + 6.25 * height - 5 * Double(ageYears) + sexConstant)
        let restingKcalPerHour = rmrPerDay / 24
        return pushupMETs * restingKcalPerHour * hours
    }

    private nonisolated static func typicalHeightCm(for sex: Sex?) -> Double {
        switch sex {
        case .male: 175
        case .female: 162
        case .other, nil: 168.5
        }
    }
}
