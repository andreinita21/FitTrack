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
                .tabItem { Label("Health Summary", systemImage: "chart.bar.xaxis") }

            ReportView()
                .tabItem { Label("Report", systemImage: "doc.text") }

            WeightView()
                .tabItem { Label("Weight", systemImage: "scalemass") }
        }
    }
}
