//
//  DayView.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI
import CoreData

struct DayView: View {
    @Environment(\.managedObjectContext) private var ctx

    // UI state
    @State private var selectedDate = Date().startOfDayLocal
    @State private var showingAddMeal = false

    // Core Data objects for the selected day
    @State private var dailyLog: DailyLog?
    @State private var bodyMetrics: BodyMetrics?

    // Use the relationship directly instead of @FetchRequest
    private var mealsSorted: [Meal] {
        let arr = (dailyLog?.meals?.allObjects as? [Meal]) ?? []
        return arr.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Date + actions
                Section {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .onChange(of: selectedDate) { _, new in rebind(to: new) }

                    HStack {
                        Button("Today") {
                            selectedDate = Date().startOfDayLocal
                            rebind(to: selectedDate)
                        }
                        Spacer()
                        Button("Import from Health") {
                            Task { await importFromHealth() }
                        }
                    }
                }

                // Sleep summary (read-only)
                if let bm = bodyMetrics,
                   let s = bm.sleepStart, let e = bm.sleepEnd, e > s {
                    Section("Sleep") {
                        Text(sleepSummary(start: s, end: e))
                            .font(.body)
                    }
                }

                // Meals
                Section("Meals") {
                    ForEach(mealsSorted, id: \.objectID) { m in
                        let time = (m.timestamp ?? Date()).formatted(date: .omitted, time: .shortened)
                        let type = m.typeRaw ?? "Meal"
                        let loc  = (m.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let desc = (m.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let parts = [time, type, loc.isEmpty ? nil : loc, desc.isEmpty ? nil : desc].compactMap { $0 }

                        Text(parts.joined(separator: " | "))
                            .lineLimit(nil)                           // allow multiline wrapping
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.body)
                            .padding(.vertical, 2)
                    }
                    .onDelete(perform: deleteMeals)

                    Button("Add Meal") { showingAddMeal = true }
                }

                // Editable body metrics
                if let bm = bodyMetrics {
                    BodySection(metrics: bm)
                }
            }
            .navigationTitle("FitTrack")
            .toolbar { EditButton() }
            .onAppear { rebind(to: selectedDate) }
            .sheet(isPresented: $showingAddMeal) {
                AddMealView(defaultDate: selectedDate) { type, time, loc, desc in
                    addMeal(type: type, at: time, location: loc, desc: desc)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Ensure there is a DailyLog for the given day and bind BodyMetrics.
    private func rebind(to day: Date) {
        // fetch or create DailyLog
        let r: NSFetchRequest<DailyLog> = DailyLog.fetchRequest()
        r.predicate = NSPredicate(format: "date == %@", day as NSDate)
        r.fetchLimit = 1

        if let existing = try? ctx.fetch(r).first {
            dailyLog = existing
        } else {
            let log = DailyLog(context: ctx)
            log.date = day
            let bm = BodyMetrics(context: ctx)
            bm.log = log
            dailyLog = log
            try? ctx.save()
        }
        bodyMetrics = dailyLog?.bodyMetrics
    }

    private func addMeal(type: String, at time: Date, location: String?, desc: String?) {
        guard let log = dailyLog else { return }
        let m = Meal(context: ctx)
        m.id = UUID()
        m.timestamp = time
        m.location = location
        m.typeRaw = type
        m.desc = desc
        m.log = log
        try? ctx.save()
    }

    private func deleteMeals(at offsets: IndexSet) {
        offsets.map { mealsSorted[$0] }.forEach(ctx.delete)
        try? ctx.save()
    }

    /// "22:45 → 06:30  (7h 45m)"
    private func sleepSummary(start s: Date, end e: Date) -> String {
        let totalSeconds = max(0, Int(e.timeIntervalSince(s)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let from = s.formatted(date: .omitted, time: .shortened)
        let to   = e.formatted(date: .omitted, time: .shortened)
        return "\(from) → \(to)  (\(hours)h \(minutes)m)"
    }

    // MARK: - Health import (READ-ONLY; fill but do not overwrite)
    private func importFromHealth() async {
        await HealthKitManager.shared.requestAuthorizationIfNeeded()
        guard let bm = bodyMetrics else { return }
        do {
            // Only fill if missing/zero

            // Sleep
            if (bm.sleepStart == nil || bm.sleepEnd == nil),
               let win = try await HealthKitManager.shared.mainSleepWindow(on: selectedDate) {
                if bm.sleepStart == nil { bm.sleepStart = win.start }
                if bm.sleepEnd == nil   { bm.sleepEnd   = win.end }
            }

            // Steps (Int32 scalar defaults to 0)
            if bm.steps == 0 {
                let steps = try await HealthKitManager.shared.stepsTotal(on: selectedDate)
                bm.steps = Int32(steps)
            }

            // Hydration (Double scalar defaults to 0)
            if bm.hydrationLiters == 0 {
                let liters = try await HealthKitManager.shared.waterLiters(on: selectedDate)
                if liters > 0 { bm.hydrationLiters = liters }
            }

            // Weight (Double scalar defaults to 0)
            if bm.weightKg == 0,
               let w = try await HealthKitManager.shared.latestWeightKg(on: selectedDate),
               w > 0 {
                bm.weightKg = w
            }

            try bm.managedObjectContext?.save()
        } catch {
            print("Health import failed:", error)
        }
    }
}
