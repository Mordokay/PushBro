//
//  WorkoutPhase.swift
//  PushBro
//

import Foundation

enum WorkoutPhase: Equatable {
    case idle
    /// Listening for the "start" voice command (camera mode with voice enabled).
    case awaitingStart
    /// Spoken countdown before detection begins; payload is seconds remaining.
    case countdown(Int)
    case active
    case summary
}
