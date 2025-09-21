//
//  FitTrackApp.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI
import CoreData

@main
struct FitTrackApp: App {
    let persistence = PersistenceController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                // Ask for Health permission & do an initial sync on first launch
                .task {
                    await HealthKitManager.shared.requestAuthorizationIfNeeded()
                    await HealthAutoSync.syncRecent(daysBack: 30, ctx: persistence.container.viewContext)
                }
        }
        // Re-run a quick sync whenever the app becomes active
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                Task { await HealthAutoSync.syncRecent(daysBack: 30, ctx: persistence.container.viewContext) }
            }
        }
    }
}
