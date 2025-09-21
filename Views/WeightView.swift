//
//  WeightView.swift
//  FitTrack
//
//  Created by Andrei Niță on 21.09.2025.
//

import SwiftUI
import CoreData

struct WeightView: View {
    @Environment(\.managedObjectContext) private var ctx

    @State private var selectedDate = Date().startOfDayLocal
    @State private var dailyLog: DailyLog?
    @State private var bodyMetrics: BodyMetrics?

    // Keep the field truly blank when no weight is logged
    @State private var weightText: String = ""

    // Insights
    @State private var totalDelta: Delta?
    @State private var monthDelta: Delta?

    var body: some View {
        NavigationStack {
            List {
                // 1) Insights at TOP
                Section("Insights") {
                    InsightCard(
                        title: "Since you began",
                        subtitle: totalDelta?.contextText ?? "Add weights to see your progress",
                        deltaText: totalDelta?.deltaText ?? "—",
                        accent: totalDelta?.color ?? .secondary
                    )

                    InsightCard(
                        title: "Last 30 days",
                        subtitle: monthDelta?.contextText ?? "Not enough recent data yet",
                        deltaText: monthDelta?.deltaText ?? "—",
                        accent: monthDelta?.color ?? .secondary
                    )
                }

                // 2) Date + Today row
                Section {
                    HStack(spacing: 12) {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: selectedDate) { _, newValue in
                                rebind(to: newValue)
                            }

                        Spacer(minLength: 8)

                        Button("Today") {
                            selectedDate = Date().startOfDayLocal
                            rebind(to: selectedDate)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // 3) Log weight
                if bodyMetrics != nil {
                    Section("Log Weight") {
                        HStack {
                            Text("Weight (kg)")
                            Spacer()
                            TextField("", text: $weightText, prompt: Text(" "))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }

                        HStack(spacing: 12) {
                            Button("Save") { saveWeight() }
                                .buttonStyle(.borderedProminent)

                            Button("Fill from Health") {
                                Task { await fillFromHealthIfEmpty(for: selectedDate) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Weight")
            .onAppear {
                rebind(to: selectedDate)
                reloadInsights()
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Day binding

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

        // load UI text (blank if 0)
        if let w = bodyMetrics?.weightKg, w > 0 {
            weightText = String(format: "%.2f", w)
        } else {
            weightText = ""
        }

        reloadInsights()
    }

    // MARK: - Save & parse

    private func saveWeight() {
        guard let bm = bodyMetrics else { return }
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            bm.weightKg = 0   // blank
        } else {
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            guard let val = Double(normalized), val >= 0 else { return }
            bm.weightKg = val
            weightText = String(format: "%.2f", val)
        }
        try? ctx.save()
        reloadInsights()
    }

    // MARK: - Health fill (read-only; only if empty)

    private func fillFromHealthIfEmpty(for day: Date) async {
        await HealthKitManager.shared.requestAuthorizationIfNeeded()
        guard let bm = bodyMetrics else { return }
        do {
            if (bm.weightKg == 0) && weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let w = try await HealthKitManager.shared.latestWeightKg(upTo: day),
               w > 0 {
                bm.weightKg = w
                weightText = String(format: "%.2f", w)
                try bm.managedObjectContext?.save()
                reloadInsights()
            }
        } catch {
            print("Weight import failed:", error)
        }
    }

    // MARK: - Insights

    private func reloadInsights() {
        let r: NSFetchRequest<BodyMetrics> = BodyMetrics.fetchRequest()
        r.predicate = NSPredicate(format: "weightKg > 0 AND log != nil")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \BodyMetrics.log?.date, ascending: true)]
        guard let rows = try? ctx.fetch(r), !rows.isEmpty else {
            totalDelta = nil; monthDelta = nil; return
        }

        let points: [(Date, Double)] = rows.compactMap { bm in
            guard let d = bm.log?.date else { return nil }
            return (d, bm.weightKg)
        }
        guard let first = points.first, let last = points.last else { return }

        totalDelta = Delta(deltaKg: last.1 - first.1,
                           startDate: first.0, endDate: last.0,
                           baselineKg: first.1)

        let thirtyAgo = Calendar.current.date(byAdding: .day, value: -30, to: last.0) ?? last.0
        if let b = points.last(where: { $0.0 <= thirtyAgo }) {
            monthDelta = Delta(deltaKg: last.1 - b.1,
                               startDate: b.0, endDate: last.0,
                               baselineKg: b.1)
        } else {
            monthDelta = nil
        }
    }
}

// MARK: - Delta + Card

private struct Delta {
    let deltaKg: Double
    let startDate: Date
    let endDate: Date
    let baselineKg: Double
    var isLoss: Bool { deltaKg < 0 }
    var color: Color { isLoss ? .green : (deltaKg > 0 ? .red : .secondary) }
    var deltaText: String {
        let sign = deltaKg > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", deltaKg)) kg"
    }
    var contextText: String {
        let pct = baselineKg > 0 ? abs(deltaKg) / baselineKg * 100.0 : 0
        let from = startDate.formatted(date: .abbreviated, time: .omitted)
        let to   = endDate.formatted(date: .abbreviated, time: .omitted)
        let verb = isLoss ? "down" : (deltaKg > 0 ? "up" : "unchanged")
        if deltaKg == 0 { return "From \(from) to \(to) (\(verb))" }
        return "\(verb) \(String(format: "%.1f", abs(deltaKg))) kg (\(String(format: "%.1f", pct))%) from \(from) to \(to)"
    }
}

private struct InsightCard: View {
    let title: String
    let subtitle: String
    let deltaText: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(deltaText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, lineWidth: 1))
    }
}
