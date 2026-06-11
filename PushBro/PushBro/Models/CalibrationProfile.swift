//
//  CalibrationProfile.swift
//  PushBro
//

import Foundation

/// Calibrated face-to-phone distances, persisted as JSON in @AppStorage.
struct CalibrationProfile: Codable, Equatable {
    /// Meters from camera to face with arms fully extended.
    var upDistance: Double
    /// Meters from camera to face at the lowest point.
    var downDistance: Double
    var createdAt: Date

    /// Calibrations with less travel than this are rejected as implausible.
    static let minimumRange: Double = 0.10

    var range: Double { upDistance - downDistance }

    var isPlausible: Bool {
        range >= Self.minimumRange && downDistance > 0
    }

    static func decode(fromJSON json: String) -> CalibrationProfile? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    func encodedJSON() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
