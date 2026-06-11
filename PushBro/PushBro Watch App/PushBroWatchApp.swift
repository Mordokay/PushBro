//
//  PushBroWatchApp.swift
//  PushBro Watch App
//

import HealthKit
import SwiftUI
import WatchKit

@main
struct PushBroWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environment(WatchWorkoutManager.shared)
        }
    }
}

/// Receives the workout configuration when the iPhone launches the watch app
/// via HKHealthStore.startWatchApp — no wrist interaction needed.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchWorkoutManager.shared.handleLaunchConfiguration()
    }
}
