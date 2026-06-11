//
//  Log.swift
//  PushBro
//
//  Shared between the iOS app and the watch app.
//

import Foundation
import os

/// Leveled, categorized logging built on os.Logger, so output lands in the
/// Xcode console and Console.app with proper subsystem/category filtering.
/// Emoji prefixes make levels scannable: 🟢 debug · 🔵 info · 🟡 warning · 🔴 error.
/// Every line is also appended to a rotating on-device log file that can be
/// shared from Settings.
nonisolated struct AppLogger: Sendable {
    private let logger: Logger
    private let category: String

    init(category: String) {
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PushBro", category: category)
        self.category = category
    }

    /// Verbose detail for development. Not persisted by the unified log
    /// (but captured in the app's own log file).
    func debug(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("🟢 [\(self.category, privacy: .public)] \(text, privacy: .public)")
        LogFileStore.shared.append("🟢 [\(category)] \(text)")
    }

    /// Notable state changes in normal operation.
    func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("🔵 [\(self.category, privacy: .public)] \(text, privacy: .public)")
        LogFileStore.shared.append("🔵 [\(category)] \(text)")
    }

    /// Something unexpected the app recovered from.
    func warning(_ message: @autoclosure () -> String) {
        let text = message()
        logger.warning("🟡 [\(self.category, privacy: .public)] \(text, privacy: .public)")
        LogFileStore.shared.append("🟡 [\(category)] \(text)")
    }

    /// A failure that degrades behavior.
    func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("🔴 [\(self.category, privacy: .public)] \(text, privacy: .public)")
        LogFileStore.shared.append("🔴 [\(category)] \(text)")
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
    /// Events relayed from the watch app, so they show up in the phone console.
    static let watch = AppLogger(category: "Watch")
}

/// Appends timestamped log lines to a file in Application Support, rotating
/// at ~2 MB (current + one previous file kept). All I/O on a utility queue.
nonisolated final class LogFileStore: @unchecked Sendable {
    static let shared = LogFileStore()

    private let queue = DispatchQueue(label: "com.greenSphereStudios.PushBro.logfile", qos: .utility)
    private let directory: URL
    private let fileURL: URL
    private let previousURL: URL
    private let formatter: DateFormatter
    private let maxBytes = 2_000_000

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("PushBroLogs", isDirectory: true)
        fileURL = directory.appendingPathComponent("pushbro.log")
        previousURL = directory.appendingPathComponent("pushbro-previous.log")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        queue.async { [directory] in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func append(_ line: String) {
        let date = Date()
        queue.async {
            let stamped = self.formatter.string(from: date) + " " + line + "\n"
            guard let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.fileURL)
            }
            self.rotateIfNeeded()
        }
    }

    private func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > maxBytes else { return }
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.moveItem(at: fileURL, to: previousURL)
    }

    /// Files that exist right now — for the share sheet.
    var existingLogFiles: [URL] {
        queue.sync {
            [fileURL, previousURL].filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    var totalSizeBytes: Int {
        queue.sync {
            [fileURL, previousURL].compactMap {
                try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int
            }.reduce(0, +)
        }
    }

    func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: self.fileURL)
            try? FileManager.default.removeItem(at: self.previousURL)
        }
    }
}
