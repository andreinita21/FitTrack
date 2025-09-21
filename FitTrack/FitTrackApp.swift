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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                // Ask for Health permissions on launch (safe if capability + plist key are set)
                .task { await HealthKitManager.shared.requestAuthorizationIfNeeded() }
        }
    }
}
