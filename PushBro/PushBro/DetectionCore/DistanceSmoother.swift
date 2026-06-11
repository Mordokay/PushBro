//
//  DistanceSmoother.swift
//  PushBro
//

import Foundation

/// Median-of-5 (kills single-frame tracking spikes) followed by an EMA
/// low-pass (~50 ms lag at 60 Hz). Resets on face loss so a reacquired
/// distance isn't dragged toward stale values.
struct DistanceSmoother {
    private var window: [Double] = []
    private var ema: Double?

    var alpha = 0.3
    var windowSize = 5

    mutating func smooth(_ value: Double?) -> Double? {
        guard let value else {
            reset()
            return nil
        }
        window.append(value)
        if window.count > windowSize {
            window.removeFirst()
        }
        let median = window.sorted()[window.count / 2]
        let smoothed = ema.map { $0 + alpha * (median - $0) } ?? median
        ema = smoothed
        return smoothed
    }

    mutating func reset() {
        window = []
        ema = nil
    }
}
