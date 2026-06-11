//
//  RootTabView.swift
//  PushBro
//

import SwiftData
import SwiftUI

enum AppTab: String {
    case workout
    case history
    case stats
    case settings
}

struct RootTabView: View {
    @AppStorage(AppSettings.hasSeenTutorialKey) private var hasSeenTutorial = false
    @AppStorage(AppSettings.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showTutorial = false
    @State private var selectedTab: AppTab = {
        #if DEBUG
        // UI-test/automation hook: launch with "-openTab stats" etc.
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-openTab"),
           index + 1 < ProcessInfo.processInfo.arguments.count,
           let tab = AppTab(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            return tab
        }
        #endif
        return .workout
    }()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Workout", systemImage: "figure.strengthtraining.traditional", value: .workout) {
                WorkoutView()
            }
            Tab("History", systemImage: "calendar", value: .history) {
                HistoryView()
            }
            Tab("Stats", systemImage: "chart.bar.fill", value: .stats) {
                StatsView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .onAppear {
            if !hasCompletedOnboarding {
                showOnboarding = true
            } else if !hasSeenTutorial {
                showTutorial = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            hasCompletedOnboarding = true
            if !hasSeenTutorial {
                showTutorial = true
            }
        } content: {
            OnboardingView()
        }
        .fullScreenCover(isPresented: $showTutorial) {
            hasSeenTutorial = true
        } content: {
            TutorialView()
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: WorkoutSession.self, inMemory: true)
}
