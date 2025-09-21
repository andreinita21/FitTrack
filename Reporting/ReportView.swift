//
//  ReportView.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI
import CoreData
import PDFKit
import UIKit

struct ReportView: View {
    @Environment(\.managedObjectContext) private var ctx
    @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!.startOfDayLocal
    @State private var end = Date().startOfDayLocal.nextDay()
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $start, displayedComponents: .date)
                DatePicker("End (exclusive)", selection: $end, displayedComponents: .date)
                Button("Generate PDF") {
                    exportURL = try? generatePDF()
                }
                if let url = exportURL {
                    ShareLink("Share Report", item: url)
                }
            }
            .navigationTitle("Report")
        }
    }

    private func fetchLogs() throws -> [DailyLog] {
        let r: NSFetchRequest<DailyLog> = DailyLog.fetchRequest()
        r.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        r.sortDescriptors = [NSSortDescriptor(keyPath: \DailyLog.date, ascending: true)]
        return try ctx.fetch(r)
    }

    private func generatePDF() throws -> URL {
        let logs = try fetchLogs()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FitTrack_Report.pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { ctx in
            for l in logs {
                ctx.beginPage()
                draw(day: l)
            }
            ctx.beginPage()
            drawStats(logs: logs)
        }
        return url
    }

    private func draw(day: DailyLog) {
        let margin: CGFloat = 36
        var y: CGFloat = margin
        func line(_ s: String, size: CGFloat = 14, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)]
            s.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
            y += size + 8
        }
        line("Date: \((day.date ?? Date()).formatted(date: .long, time: .omitted))", size: 18, bold: true)
        line("Meals:", size: 16, bold: true)
        let meals = (day.meals?.allObjects as? [Meal] ?? [])
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        for m in meals {
            let t = m.timestamp ?? Date()
            let type = m.typeRaw ?? ""
            let loc = m.location ?? ""
            let dsc = m.desc ?? ""
            line("• \(t.formatted(date: .omitted, time: .shortened))  \(type)  \(loc)  \(dsc)")
        }
        line("Body:", size: 16, bold: true)
        if let b = day.bodyMetrics {
            if let s = b.sleepStart, let e = b.sleepEnd {
                let h = e.timeIntervalSince(s)/3600
                line("Sleep: \(s.formatted(date: .omitted, time: .shortened)) → \(e.formatted(date: .omitted, time: .shortened)) (\(String(format: "%.1f", h)) h)")
            }
            if let b = day.bodyMetrics {
                if let s = b.sleepStart, let e = b.sleepEnd {
                    let h = e.timeIntervalSince(s)/3600
                    line("Sleep: \(s.formatted(date: .omitted, time: .shortened)) → \(e.formatted(date: .omitted, time: .shortened)) (\(String(format: "%.1f", h)) h)")
                }
                line("Steps: \(Int(b.steps))")
                line("Weight: \(String(format: "%.1f", b.weightKg)) kg")
                line("Hydration: \(String(format: "%.1f", b.hydrationLiters)) L")
            }
        }
    }

    private func drawStats(logs: [DailyLog]) {
        let margin: CGFloat = 36
        var y: CGFloat = margin
        func line(_ s: String, size: CGFloat = 16, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)]
            s.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
            y += size + 10
        }
        line("Stats", size: 22, bold: true)

        // Weight delta (first vs last available)
        let weights = logs.compactMap { $0.bodyMetrics?.weightKg }
        if let first = weights.first, let last = weights.last {
            let delta = last - first
            line("You have \(delta <= 0 ? "lost" : "gained") \(String(format: "%.1f", abs(delta))) kg")
        } else { line("You have lost N/A kg") }

        // Avg sleep
        let sleeps = logs.compactMap { l -> Double? in
            guard let s = l.bodyMetrics?.sleepStart, let e = l.bodyMetrics?.sleepEnd else { return nil }
            return e.timeIntervalSince(s)/3600
        }
        if !sleeps.isEmpty {
            let avg = sleeps.reduce(0,+)/Double(sleeps.count)
            line("You averaged a sleep duration of \(String(format: "%.1f", avg)) hours")
        } else { line("You averaged a sleep duration of N/A hours") }

        // Avg steps
        let steps = logs.compactMap { $0.bodyMetrics }.map { Int($0.steps) }
        if !steps.isEmpty {
            let avg = steps.reduce(0,+) / steps.count
            line("You averaged a number of \(avg) steps/day")
        } else {
            line("You averaged a number of N/A steps/day")
        }
    }
}
