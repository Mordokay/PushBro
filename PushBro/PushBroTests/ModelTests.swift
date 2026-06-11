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

    @Test func calorieEstimateUsesMETFormula() {
        // 8 METs × 75 kg × 1 h = 600 kcal
        #expect(HealthKitManager.estimatedKilocalories(weightKg: 75, activeSeconds: 3600) == 600)
        // 8 × 80 × 0.05 h = 32 kcal for a 3-minute session
        #expect(abs((HealthKitManager.estimatedKilocalories(weightKg: 80, activeSeconds: 180) ?? 0) - 32) < 0.0001)
        #expect(HealthKitManager.estimatedKilocalories(weightKg: 0, activeSeconds: 600) == nil)
        #expect(HealthKitManager.estimatedKilocalories(weightKg: 75, activeSeconds: 0) == nil)
    }

    @Test func calibrationProfileJSONRoundTrip() throws {
        let profile = CalibrationProfile(upDistance: 0.45, downDistance: 0.18, createdAt: Date(timeIntervalSince1970: 1_750_000_000))
        let decoded = try #require(CalibrationProfile.decode(fromJSON: profile.encodedJSON()))
        #expect(decoded == profile)
        #expect(profile.isPlausible)
        #expect(!CalibrationProfile(upDistance: 0.30, downDistance: 0.25, createdAt: .now).isPlausible)
    }
}
