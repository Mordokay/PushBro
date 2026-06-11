//
//  ModelTests.swift
//  PushBroTests
//

import Foundation
import SwiftData
import Testing
@testable import PushBro

struct ModelTests {
    @Test func sessionRoundTrip() throws {
        let container = try ModelContainer(
            for: WorkoutSession.self, WorkoutSet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let session = WorkoutSession(startDate: start, endDate: start.addingTimeInterval(120), mode: .camera)
        let set1 = WorkoutSet(index: 0, startDate: start, endDate: start.addingTimeInterval(40), repOffsets: [2, 4.5, 7, 9.5])
        let set2 = WorkoutSet(index: 1, startDate: start.addingTimeInterval(70), endDate: start.addingTimeInterval(100), repOffsets: [2, 5, 8])
        session.sets = [set2, set1]
        session.totalReps = set1.repCount + set2.repCount
        context.insert(session)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched.count == 1)
        let loaded = try #require(fetched.first)
        #expect(loaded.mode == .camera)
        #expect(loaded.totalReps == 7)
        #expect(loaded.orderedSets.map(\.repCount) == [4, 3])
        #expect(loaded.orderedSets[0].repIntervals == [2.5, 2.5, 2.5])
        #expect(loaded.duration == 120)
    }

    @Test func cascadeDelete() throws {
        let container = try ModelContainer(
            for: WorkoutSession.self, WorkoutSet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let now = Date()
        let session = WorkoutSession(startDate: now, endDate: now.addingTimeInterval(60), mode: .manual)
        session.sets = [WorkoutSet(index: 0, startDate: now, endDate: now.addingTimeInterval(30), repOffsets: [1, 2])]
        context.insert(session)
        try context.save()

        context.delete(session)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
    }

    @Test func calorieEstimateFallsBackToClassicMETWithoutAge() {
        // 8 METs × 75 kg × 1 h = 600 kcal
        #expect(HealthKitManager.estimatedKilocalories(weightKg: 75, activeSeconds: 3600) == 600)
        // 8 × 80 × 0.05 h = 32 kcal for a 3-minute session
        #expect(abs((HealthKitManager.estimatedKilocalories(weightKg: 80, activeSeconds: 180) ?? 0) - 32) < 0.0001)
        #expect(HealthKitManager.estimatedKilocalories(weightKg: 0, activeSeconds: 600) == nil)
        #expect(HealthKitManager.estimatedKilocalories(weightKg: 75, activeSeconds: 0) == nil)
    }

    @Test func calorieEstimateUsesMifflinStJeorWithProfile() {
        // Male, 30 y, 75 kg, 175 cm: RMR = 750 + 1093.75 − 150 + 5 = 1698.75/day
        // → 8 METs × (1698.75 / 24) × 1 h = 566.25 kcal
        let male = HealthKitManager.estimatedKilocalories(
            weightKg: 75, activeSeconds: 3600, ageYears: 30, sex: .male, heightCm: 175
        )
        #expect(abs((male ?? 0) - 566.25) < 0.0001)

        // Female, 60 y, 75 kg, 160 cm: RMR = 750 + 1000 − 300 − 161 = 1289/day
        // → 8 × (1289 / 24) = 429.67 kcal/h
        let female = HealthKitManager.estimatedKilocalories(
            weightKg: 75, activeSeconds: 3600, ageYears: 60, sex: .female, heightCm: 160
        )
        #expect(abs((female ?? 0) - 8 * 1289.0 / 24) < 0.0001)

        // Same person, classic formula would say 600 for both — the corrected
        // estimate separates them.
        #expect((male ?? 0) > (female ?? 0))
    }

    @Test func calorieEstimateHandlesMissingHeightAndOtherSex() {
        // Missing height falls back to a sex-typical height (175 cm male).
        let defaulted = HealthKitManager.estimatedKilocalories(
            weightKg: 75, activeSeconds: 3600, ageYears: 30, sex: .male
        )
        let explicit = HealthKitManager.estimatedKilocalories(
            weightKg: 75, activeSeconds: 3600, ageYears: 30, sex: .male, heightCm: 175
        )
        #expect(defaulted == explicit)

        // "Other"/unknown sex uses the midpoint constant: −78.
        // RMR = 750 + 6.25×168.5 − 150 − 78 = 1575.125 → ×8/24 = 525.04 kcal/h
        let other = HealthKitManager.estimatedKilocalories(
            weightKg: 75, activeSeconds: 3600, ageYears: 30, sex: .other
        )
        #expect(abs((other ?? 0) - 8 * 1575.125 / 24) < 0.0001)

        // Implausible inputs clamp at the RMR floor instead of going negative.
        let extreme = HealthKitManager.estimatedKilocalories(
            weightKg: 20, activeSeconds: 3600, ageYears: 120, sex: .female, heightCm: 100
        )
        #expect((extreme ?? 0) == 8 * 500.0 / 24)
    }

    @Test func calibrationProfileJSONRoundTrip() throws {
        let profile = CalibrationProfile(upDistance: 0.45, downDistance: 0.18, createdAt: Date(timeIntervalSince1970: 1_750_000_000))
        let decoded = try #require(CalibrationProfile.decode(fromJSON: profile.encodedJSON()))
        #expect(decoded == profile)
        #expect(profile.isPlausible)
        #expect(!CalibrationProfile(upDistance: 0.30, downDistance: 0.25, createdAt: .now).isPlausible)
    }
}
