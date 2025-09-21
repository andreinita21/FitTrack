//
//  ContentView.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DayView()
                .tabItem { Label("Today", systemImage: "calendar") }

            ReportView()
                .tabItem { Label("Report", systemImage: "doc.plaintext") }
        }
    }
}

#Preview { ContentView() }
