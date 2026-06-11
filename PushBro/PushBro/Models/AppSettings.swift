//
//  AppSettings.swift
//  PushBro
//

import Foundation

/// @AppStorage keys and defaults, in one place so views and the engine agree.
enum AppSettings {
    static let dailyGoalKey = "dailyGoal"
    static let restThresholdKey = "restThresholdSeconds"
    static let downThresholdKey = "downThresholdPercent"
    static let voiceCommandsEnabledKey = "voiceCommandsEnabled"
    static let spokenCountEnabledKey = "spokenCountEnabled"
    static let healthKitEnabledKey = "healthKitEnabled"
    static let calibrationJSONKey = "calibrationJSON"
    static let startTimerSecondsKey = "startTimerSeconds"
    static let hasSeenTutorialKey = "hasSeenTutorial"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let preferredModeKey = "preferredMode"
    static let userNameKey = "userName"
    /// 0 = not provided. Used for Apple Health calorie estimates.
    static let bodyWeightKgKey = "bodyWeightKg"
    /// Sex.rawValue; empty = not provided.
    static let userSexKey = "userSex"
    /// 0 = not provided.
    static let userAgeKey = "userAge"
    /// 0 = not provided. Improves calorie estimates (Mifflin-St Jeor).
    static let userHeightCmKey = "userHeightCm"
    static let watchHeartRateEnabledKey = "watchHeartRateEnabled"
    /// GoalHistory JSON — per-day goal tracking for charts and streaks.
    static let goalHistoryJSONKey = "goalHistoryJSON"
    /// Epoch seconds of the first app launch; 0 = unset. Combined with the
    /// earliest session date to know when the user started using the app.
    static let firstLaunchDateKey = "firstLaunchDate"

    static let defaultDailyGoal = 50
    static let defaultRestThreshold = 4.0
    static let defaultDownThreshold = Difficulty.medium.downThreshold
    static let defaultStartTimerSeconds = 5
}

enum Sex: String, CaseIterable, Identifiable {
    case male
    case female
    case other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Named difficulty presets. The settings slider is continuous; these are its landmarks.
enum Difficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    /// Fraction of the calibrated range the user must descend for a rep to count.
    var downThreshold: Double {
        switch self {
        case .easy: 0.60
        case .medium: 0.75
        case .hard: 0.90
        }
    }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }

    /// The preset nearest to a slider value, for display.
    static func nearest(toDownThreshold value: Double) -> Difficulty {
        allCases.min { abs($0.downThreshold - value) < abs($1.downThreshold - value) } ?? .medium
    }
}
