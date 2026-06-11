//
//  RootTabView.swift
//  PushBro
//

import SwiftData
import SwiftUI

struct RootTabView: View {
    @AppStorage(AppSettings.hasSeenTutorialKey) private var hasSeenTutorial = false
    @AppStorage(AppSettings.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showTutorial = false

    var body: some View {
        TabView {
            Tab("Workout", systemImage: "figure.strengthtraining.traditional") {
                WorkoutView()
            }
            Tab("History", systemImage: "calendar") {
                HistoryView()
            }
            Tab("Stats", systemImage: "chart.bar.fill") {
                StatsView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
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
