//
//  WorkoutEngineTests.swift
//  PushBroTests
//

import Foundation
import SwiftData
import Testing
@testable import PushBro

struct WorkoutEngineTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: WorkoutSession.self, WorkoutSet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func repsSplitIntoSetsByRestGap() throws {
        let engine = WorkoutEngine()
        engine.restThreshold = 4.0
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        engine.begin(at: t0)

        // Set 1: four reps 2s apart.
        for i in 0..<4 {
            engine.recordRep(at: t0.addingTimeInterval(Double(i) * 2))
        }
        #expect(engine.currentSetReps == 4)
        #expect(engine.setNumber == 1)

        // 10s rest, then set 2: three reps.
        let t1 = t0.addingTimeInterval(16)
        for i in 0..<3 {
            engine.recordRep(at: t1.addingTimeInterval(Double(i) * 2))
        }
        #expect(engine.setNumber == 2)
        #expect(engine.currentSetReps == 3)
        #expect(engine.totalReps == 7)

        let context = try makeContext()
        engine.stop(at: t1.addingTimeInterval(6), context: context)
        #expect(engine.phase == .summary)

        let session = try #require(engine.finishedSession)
        #expect(session.totalReps == 7)
        #expect(session.orderedSets.map(\.repCount) == [4, 3])
        #expect(session.orderedSets[0].repOffsets == [0, 2, 4, 6])
        #expect(session.orderedSets[0].duration == 6)
        // Session spans first rep's set start through last rep.
        #expect(session.endDate == t1.addingTimeInterval(4))

        let fetched = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(fetched.count == 1)
    }

    @Test func zeroRepSessionIsDiscarded() throws {
        let engine = WorkoutEngine()
        engine.begin()
        let context = try makeContext()
        engine.stop(context: context)

        #expect(engine.phase == .idle)
        #expect(engine.finishedSession == nil)
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    }

    @Test func repsIgnoredOutsideActivePhase() throws {
        let engine = WorkoutEngine()
        engine.recordRep()
        #expect(engine.totalReps == 0)

        engine.begin()
        engine.recordRep()
        let context = try makeContext()
        engine.stop(context: context)
        engine.recordRep()
        #expect(engine.finishedSession?.totalReps == 1)
    }

    @Test func dismissSummaryResetsEverything() throws {
        let engine = WorkoutEngine()
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        engine.begin(at: t0)
        engine.recordRep(at: t0)
        engine.recordRep(at: t0.addingTimeInterval(2))

        let context = try makeContext()
        engine.stop(at: t0.addingTimeInterval(3), context: context)
        engine.dismissSummary()

        #expect(engine.phase == .idle)
        #expect(engine.totalReps == 0)
        #expect(engine.setNumber == 1)
        #expect(engine.sessionStart == nil)
        #expect(engine.finishedSession == nil)
    }

    @Test func singleRepHasZeroOffsetAndZeroDuration() throws {
        let engine = WorkoutEngine()
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        engine.begin(at: t0)
        engine.recordRep(at: t0.addingTimeInterval(5))

        let context = try makeContext()
        engine.stop(at: t0.addingTimeInterval(8), context: context)
        let session = try #require(engine.finishedSession)
        #expect(session.orderedSets.count == 1)
        #expect(session.orderedSets[0].repOffsets == [0])
        #expect(session.orderedSets[0].duration == 0)
    }
}
