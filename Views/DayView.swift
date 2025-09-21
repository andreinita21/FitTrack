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
    @State private var refreshTick = 0   // forces meals list refresh after add/delete

    // Health import range (inclusive)
    @State private var rangeStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!.startOfDayLocal
    @State private var rangeEnd   = Date().startOfDayLocal

    // Core Data objects for the selected day
    @State private var dailyLog: DailyLog?
    @State private var bodyMetrics: BodyMetrics?

    // Meals derived from the relationship, sorted by time
    private var mealsSorted: [Meal] {
        let arr = (dailyLog?.meals?.allObjects as? [Meal]) ?? []
        return arr.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                // 1) Date picker (compact) + Today button on the same row
                Section {
                    HStack(spacing: 12) {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: selectedDate) { _, new in rebind(to: new) }

                        Spacer(minLength: 8)

                        Button("Today") {
                            selectedDate = Date().startOfDayLocal
                            rebind(to: selectedDate)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // 2) Add Meal (no title, only the button)
                Section {
                    Button(action: { showingAddMeal = true }) {
                        Label("Add Meal", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4)
                }

                // 3) Meals list
                Section("Meals") {
                    if mealsSorted.isEmpty {
                        Text("No meals logged yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(mealsSorted, id: \.objectID) { m in
                            let time = (m.timestamp ?? Date()).formatted(date: .omitted, time: .shortened)
                            let type = m.typeRaw ?? "Meal"
                            let loc  = (m.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let desc = (m.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let parts = [time, type, loc.isEmpty ? nil : loc, desc.isEmpty ? nil : desc].compactMap { $0 }

                            Text(parts.joined(separator: " | "))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.body)
                                .padding(.vertical, 2)
                        }
                        .onDelete(perform: deleteMeals)   // <- stays on ForEach
                    }
                }
                .id(refreshTick)                           // <- moved here

                // 4) Sleep (read-only summary)
                if let bm = bodyMetrics,
                   let s = bm.sleepStart, let e = bm.sleepEnd, e > s {
                    Section("Sleep") {
                        Text(sleepSummary(start: s, end: e))
                            .font(.body)
                    }
                }

                // 5) Body (editable)
                if let bm = bodyMetrics {
                    BodySection(metrics: bm)
                }

                // 6) Import data from Health
                Section("Import data from Health") {
                    DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("To",   selection: $rangeEnd,   displayedComponents: .date)

                    Button {
                        Task { await importRangeFromHealth(start: rangeStart, endInclusive: rangeEnd) }
                    } label: {
                        // Icon on the RIGHT of the word "Import"
                        HStack {
                            Text("Import").fontWeight(.semibold)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("FitTrack")
            .scrollDismissesKeyboard(.interactively)
            .toolbar { EditButton() }
            .onAppear { rebind(to: selectedDate) }
            .sheet(isPresented: $showingAddMeal) {
                    AddMealView(defaultDate: selectedDate) { type, time, loc, desc in
                        addMeal(type: type, at: time, location: loc, desc: desc)
                    }
            }
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
        // bump so the meals list recomputes when changing days
        refreshTick &+= 1
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
        refreshTick &+= 1
    }

    private func deleteMeals(at offsets: IndexSet) {
        offsets.map { mealsSorted[$0] }.forEach(ctx.delete)
        try? ctx.save()
        refreshTick &+= 1
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

    private func importDayFromHealth(_ day: Date) async {
        await HealthKitManager.shared.requestAuthorizationIfNeeded()
        rebind(to: day)
        guard let bm = bodyMetrics else { return }
        do {
            if (bm.sleepStart == nil || bm.sleepEnd == nil),
               let win = try await HealthKitManager.shared.mainSleepWindow(on: day) {
                if bm.sleepStart == nil { bm.sleepStart = win.start }
                if bm.sleepEnd == nil   { bm.sleepEnd   = win.end }
            }
            if bm.steps == 0 {
                let steps = try await HealthKitManager.shared.stepsTotal(on: day)
                bm.steps = Int32(steps)
            }
            if bm.hydrationLiters == 0 {
                let liters = try await HealthKitManager.shared.waterLiters(on: day)
                if liters > 0 { bm.hydrationLiters = liters }
            }
            if bm.weightKg == 0,
               let w = try await HealthKitManager.shared.latestWeightKg(upTo: day),
               w > 0 {
                bm.weightKg = w
            }
            try bm.managedObjectContext?.save()
            refreshTick &+= 1
        } catch {
            print("Health import failed:", error)
        }
    }

    /// Inclusive range import
    private func importRangeFromHealth(start: Date, endInclusive: Date) async {
        await HealthKitManager.shared.requestAuthorizationIfNeeded()
        let cal = Calendar.current
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: endInclusive)
        while day <= last {
            await importDayFromHealth(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        rebind(to: selectedDate) // ensure current day’s UI is fresh
    }
}
