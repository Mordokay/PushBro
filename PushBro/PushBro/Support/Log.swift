//
//  Log.swift
//  PushBro
//

import Foundation
import os

/// Leveled, categorized logging built on os.Logger, so output lands in the
/// Xcode console and Console.app with proper subsystem/category filtering.
/// Emoji prefixes make levels scannable: 🟢 debug · 🔵 info · 🟡 warning · 🔴 error.
nonisolated struct AppLogger: Sendable {
    private let logger: Logger
    private let category: String

    init(category: String) {
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PushBro", category: category)
        self.category = category
    }

    /// Verbose detail for development. Not persisted by the unified log.
    func debug(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("🟢 [\(self.category, privacy: .public)] \(text, privacy: .public)")
    }

    /// Notable state changes in normal operation.
    func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("🔵 [\(self.category, privacy: .public)] \(text, privacy: .public)")
    }

    /// Something unexpected the app recovered from.
    func warning(_ message: @autoclosure () -> String) {
        let text = message()
        logger.warning("🟡 [\(self.category, privacy: .public)] \(text, privacy: .public)")
    }

    /// A failure that degrades behavior.
    func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("🔴 [\(self.category, privacy: .public)] \(text, privacy: .public)")
    }
}

/// One logger per subsystem area. Add categories here, not ad-hoc Loggers.
nonisolated enum Log {
    static let app = AppLogger(category: "App")
    static let workout = AppLogger(category: "Workout")
    static let calibration = AppLogger(category: "Calibration")
    static let detection = AppLogger(category: "Detection")
    static let voice = AppLogger(category: "Voice")
    static let audio = AppLogger(category: "Audio")
    static let health = AppLogger(category: "Health")
    static let data = AppLogger(category: "Data")
}
