//
//  RepCounterStateMachine.swift
//  PushBro
//

import Foundation

/// Pure rep-counting state machine. Feed it (smoothed) distance samples and
/// it emits rep events. All timing comes from sample timestamps — no clocks,
/// no timers — so canned traces replay deterministically in tests.
struct RepCounterStateMachine {
    enum State: Equatable {
        /// Initial / after reacquire: must hold the up zone briefly to arm.
        case waitingForUp(upZoneSince: TimeInterval?)
        /// Up and ready; a descent starts a rep attempt.
        case armed(upZoneSince: TimeInterval, restEmitted: Bool)
        /// Past the up threshold on the way down.
        case descending(maxDepth: Double)
        /// Down threshold reached; rising back to the up zone completes the rep.
        case bottomReached
        /// Face untracked beyond the grace interval.
        case faceLost(since: TimeInterval, hadBottom: Bool, restEmitted: Bool)
    }

    private(set) var state: State = .waitingForUp(upZoneSince: nil)
    private(set) var repCount = 0
    /// Latest normalized depth, for a live depth bar. Nil while untracked.
    private(set) var currentDepth: Double?

    let config: RepDetectionConfig

    private var nilSince: TimeInterval?

    init(config: RepDetectionConfig) {
        self.config = config
    }

    mutating func process(_ sample: DistanceSample) -> [RepEvent] {
        guard let distance = sample.distance else {
            return processUntracked(at: sample.timestamp)
        }
        nilSince = nil
        let depth = config.depth(forDistance: distance)
        currentDepth = depth
        return processDepth(depth, at: sample.timestamp)
    }

    mutating func reset() {
        state = .waitingForUp(upZoneSince: nil)
        repCount = 0
        currentDepth = nil
        nilSince = nil
    }

    // MARK: - Tracked

    private mutating func processDepth(_ depth: Double, at time: TimeInterval) -> [RepEvent] {
        var events: [RepEvent] = []

        // Coming back from face loss.
        if case .faceLost(_, let hadBottom, _) = state {
            events.append(.faceReacquired)
            state = hadBottom ? .bottomReached : .waitingForUp(upZoneSince: nil)
        }

        switch state {
        case .waitingForUp(let upZoneSince):
            if depth <= config.upThreshold {
                if let since = upZoneSince {
                    if time - since >= config.armingDuration {
                        state = .armed(upZoneSince: since, restEmitted: false)
                    }
                } else {
                    state = .waitingForUp(upZoneSince: time)
                }
            } else {
                state = .waitingForUp(upZoneSince: nil)
            }

        case .armed(let upZoneSince, let restEmitted):
            if depth > config.upThreshold {
                state = .descending(maxDepth: depth)
            } else if !restEmitted, time - upZoneSince > config.restThreshold {
                events.append(.restDetected)
                state = .armed(upZoneSince: upZoneSince, restEmitted: true)
            }

        case .descending(let maxDepth):
            let newMax = max(maxDepth, depth)
            if depth >= config.downThreshold {
                events.append(.reachedBottom)
                state = .bottomReached
            } else if depth <= config.upThreshold {
                events.append(.partialRepRejected)
                state = .armed(upZoneSince: time, restEmitted: false)
            } else {
                state = .descending(maxDepth: newMax)
            }

        case .bottomReached:
            if depth <= config.upThreshold {
                repCount += 1
                events.append(.repCompleted(count: repCount))
                state = .armed(upZoneSince: time, restEmitted: false)
            }

        case .faceLost:
            break // handled above
        }

        return events
    }

    // MARK: - Untracked

    private mutating func processUntracked(at time: TimeInterval) -> [RepEvent] {
        currentDepth = nil

        if case .faceLost(let since, let hadBottom, let restEmitted) = state {
            if !restEmitted, time - since > config.restThreshold {
                state = .faceLost(since: since, hadBottom: hadBottom, restEmitted: true)
                return [.restDetected]
            }
            return []
        }

        if nilSince == nil {
            nilSince = time
        }
        guard let nilSince, time - nilSince >= config.faceLossGrace else {
            return []
        }

        // The chin often drops below the sensor's minimum range right at the
        // bottom of a rep: a deep descent that loses the face counts as
        // having reached the bottom.
        var events: [RepEvent] = [.faceLost]
        var hadBottom = false
        switch state {
        case .bottomReached:
            hadBottom = true
        case .descending(let maxDepth) where maxDepth >= config.deepFaceLossFraction * config.downThreshold:
            events.insert(.reachedBottom, at: 0)
            hadBottom = true
        default:
            break
        }
        state = .faceLost(since: nilSince, hadBottom: hadBottom, restEmitted: false)
        return events
    }
}
