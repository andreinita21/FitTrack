//
//  InsightsView.swift
//  FitTrack
//
//  Created by Andrei Niță on 21.09.2025.
//

import SwiftUI
import CoreData

struct InsightsView: View {
    @Environment(\.managedObjectContext) private var ctx

    @State private var totalDelta: Delta?
    @State private var monthDelta: Delta?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InsightCard(
                        title: "Since you began",
                        subtitle: totalDelta?.contextText ?? "Add some weights to see your progress",
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
                .padding()
            }
            .navigationTitle("Insights")
            .onAppear { reload() }
        }
    }

    private func reload() {
        // Fetch all BodyMetrics with weight > 0, sorted by date
        let r: NSFetchRequest<BodyMetrics> = BodyMetrics.fetchRequest()
        r.predicate = NSPredicate(format: "weightKg > 0 AND log != nil")
        r.sortDescriptors = [NSSortDescriptor(keyPath: \BodyMetrics.log?.date, ascending: true)]

        guard let rows = try? ctx.fetch(r), !rows.isEmpty else {
            totalDelta = nil
            monthDelta = nil
            return
        }

        // Map to (date, weight)
        let points: [(Date, Double)] = rows.compactMap { bm in
            guard let d = bm.log?.date else { return nil }
            return (d, bm.weightKg)
        }

        guard let first = points.first, let last = points.last else { return }

        // Total delta
        let total = last.1 - first.1
        totalDelta = Delta(deltaKg: total,
                           startDate: first.0,
                           endDate: last.0,
                           baselineKg: first.1)

        // 30-day delta
        let thirtyAgo = Calendar.current.date(byAdding: .day, value: -30, to: last.0) ?? last.0
        // find the closest entry at or before 30 days ago
        let baseline30 = points.last(where: { $0.0 <= thirtyAgo })
        if let b = baseline30 {
            let d = last.1 - b.1
            monthDelta = Delta(deltaKg: d,
                               startDate: b.0,
                               endDate: last.0,
                               baselineKg: b.1)
        } else {
            monthDelta = nil
        }
    }
}

// MARK: - Model for a delta

private struct Delta {
    let deltaKg: Double
    let startDate: Date
    let endDate: Date
    let baselineKg: Double

    var isLoss: Bool { deltaKg < 0 }
    var color: Color { isLoss ? .green : (deltaKg > 0 ? .red : .secondary) }

    var deltaText: String {
        let sign = deltaKg > 0 ? "+" : "" // minus included by formatter
        return "\(sign)\(String(format: "%.1f", deltaKg)) kg"
    }

    var contextText: String {
        let pct = baselineKg > 0 ? abs(deltaKg) / baselineKg * 100.0 : 0
        let from = startDate.formatted(date: .abbreviated, time: .omitted)
        let to = endDate.formatted(date: .abbreviated, time: .omitted)
        let verb = isLoss ? "down" : (deltaKg > 0 ? "up" : "unchanged")
        if deltaKg == 0 { return "From \(from) to \(to) (\(verb))" }
        return "\(verb) \(String(format: "%.1f", abs(deltaKg))) kg (\(String(format: "%.1f", pct))%) from \(from) to \(to)"
    }
}

// MARK: - UI Card

private struct InsightCard: View {
    let title: String
    let subtitle: String
    let deltaText: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
