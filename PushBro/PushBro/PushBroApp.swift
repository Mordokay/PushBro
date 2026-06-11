//
//  PushBroApp.swift
//  PushBro
//
//  Created by Pedro Saldanha on 11/06/2026.
//

import SwiftUI
import SwiftData

@main
struct PushBroApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WorkoutSession.self,
            WorkoutSet.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            Log.data.error("Could not create ModelContainer: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        if UserDefaults.standard.double(forKey: AppSettings.firstLaunchDateKey) == 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppSettings.firstLaunchDateKey)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedData") {
            DebugSeed.populate(context: sharedModelContainer.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
