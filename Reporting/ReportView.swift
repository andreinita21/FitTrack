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
import UniformTypeIdentifiers

struct ReportView: View {
    @Environment(\.managedObjectContext) private var ctx

    // Date range (End is exclusive in queries)
    @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!.startOfDayLocal
    @State private var end   = Date().startOfDayLocal.nextDay()

    // Outputs
    @State private var exportURL: URL?

    // DB export/import UI
    @State private var showingExporter = false
    @State private var exportFolder: URL?
    @State private var showingImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // ----- Report Range -----
                Section("Report Range") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End (exclusive)", selection: $end, displayedComponents: .date)
                    Button("Generate PDF") {
                        exportURL = try? generatePDF()
                    }
                    if let url = exportURL {
                        ShareLink("Share Report", item: url)
                    }
                }

                // ----- Database backup -----
                Section("Database") {
                    Button("Export Database") {
                        do {
                            importMessage = nil
                            exportFolder = try PersistenceController.shared.exportDatabaseFolder()
                            showingExporter = true
                        } catch {
                            importMessage = "Export failed: \(error.localizedDescription)"
                        }
                    }
                    .fileExporter(
                        isPresented: $showingExporter,
                        document: FolderDocument(url: exportFolder),
                        contentType: .folder,
                        defaultFilename: exportDefaultName()
                    ) { result in
                        if let folder = exportFolder {
                            try? FileManager.default.removeItem(at: folder)   // cleanup temp
                            exportFolder = nil
                        }
                        switch result {
                        case .success: importMessage = "Export complete."
                        case .failure(let err): importMessage = "Export failed: \(err.localizedDescription)"
                        }
                    }

                    Button("Import Database") { showingImporter = true }
                    .fileImporter(
                        isPresented: $showingImporter,
                        allowedContentTypes: [.folder],
                        allowsMultipleSelection: false
                    ) { res in
                        switch res {
                        case .success(let urls):
                            guard let url = urls.first else { return }
                            do {
                                try PersistenceController.shared.importDatabaseFolder(from: url)
                                importMessage = "Import complete. If views look stale, relaunch the app."
                            } catch {
                                importMessage = "Import failed: \(error.localizedDescription)"
                            }
                        case .failure(let err):
                            importMessage = "Import cancelled: \(err.localizedDescription)"
                        }
                    }

                    if let msg = importMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Report")
        }
    }

    // MARK: - Fetch

    private func fetchLogs() throws -> [DailyLog] {
        let r: NSFetchRequest<DailyLog> = DailyLog.fetchRequest()
        r.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        r.sortDescriptors = [NSSortDescriptor(keyPath: \DailyLog.date, ascending: true)]
        return try ctx.fetch(r)
    }

    // MARK: - PDF

    private func generatePDF() throws -> URL {
        let logs = try fetchLogs()

        // Build filename: FitTrackReport_09Sep25_26Sep25.pdf
        let displayEnd = inclusiveDisplayEnd(from: end) // convert exclusive to inclusive for the name
        let fname = "FitTrackReport_\(filenameDate(start))_\(filenameDate(displayEnd)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fname)

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

    // MARK: - Drawing helpers

    /// Wrap a string at word boundaries to max characters per printed row.
    private func wrappedLines(_ text: String, max: Int = 70) -> [String] {
        guard text.count > max else { return [text] }
        var out: [String] = []
        var current = ""
        // Split on spaces but keep gaps between words
        for token in text.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(token)
            if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= max {
                current += " " + w
            } else {
                out.append(current)
                current = w
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private func draw(day: DailyLog) {
        let margin: CGFloat = 36
        var y: CGFloat = margin

        func line(_ s: String, size: CGFloat = 14, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
            ]
            for wrapped in wrappedLines(s, max: 70) {
                wrapped.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
                y += size + 4
            }
            y += 4 // extra spacing between logical lines
        }

        // Header
        line("Date: \((day.date ?? Date()).formatted(date: .long, time: .omitted))", size: 18, bold: true)

        // Meals with pipes + wrapping
        line("Meals:", size: 16, bold: true)
        let meals = (day.meals?.allObjects as? [Meal] ?? [])
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        for m in meals {
            let t = (m.timestamp ?? Date()).formatted(date: .omitted, time: .shortened)
            let type = m.typeRaw ?? ""
            let loc = (m.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dsc = (m.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [t, type, loc.isEmpty ? nil : loc, dsc.isEmpty ? nil : dsc].compactMap { $0 }
            line("• " + parts.joined(separator: " | "))
        }

        // Body (sleep as h m)
        line("Body:", size: 16, bold: true)
        if let b = day.bodyMetrics {
            if let s = b.sleepStart, let e = b.sleepEnd {
                let secs = max(0, Int(e.timeIntervalSince(s)))
                let h = secs / 3600
                let m = (secs % 3600) / 60
                let sum = "\(s.formatted(date: .omitted, time: .shortened)) → \(e.formatted(date: .omitted, time: .shortened)) (\(h)h \(m)m)"
                line("Sleep: " + sum)
            }
            line("Steps: \(Int(b.steps))")
            line("Weight: \(String(format: "%.1f", b.weightKg)) kg")
            line("Hydration: \(String(format: "%.1f", b.hydrationLiters)) L")
        }
    }

    private func drawStats(logs: [DailyLog]) {
        let margin: CGFloat = 36
        var y: CGFloat = margin

        func line(_ s: String, size: CGFloat = 16, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
            ]
            for wrapped in wrappedLines(s, max: 70) {
                wrapped.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
                y += size + 6
            }
            y += 4
        }

        line("Stats", size: 22, bold: true)

        // Weight delta (first vs last available)
        let weights = logs.compactMap { $0.bodyMetrics?.weightKg }
        if let first = weights.first, let last = weights.last {
            let delta = last - first
            line("You have \(delta <= 0 ? "lost" : "gained") \(String(format: "%.1f", abs(delta))) kg")
        } else {
            line("You have lost N/A kg")
        }

        // Avg sleep as h m
        let sleepDurationsSec = logs.compactMap { l -> Int? in
            guard let s = l.bodyMetrics?.sleepStart, let e = l.bodyMetrics?.sleepEnd else { return nil }
            return max(0, Int(e.timeIntervalSince(s)))
        }
        if let avgSec = sleepDurationsSec.average() {
            let h = avgSec / 3600
            let m = (avgSec % 3600) / 60
            line("You averaged a sleep duration of \(h)h \(m)m")
        } else {
            line("You averaged a sleep duration of N/A")
        }

        // Avg steps
        let steps = logs.map { Int($0.bodyMetrics?.steps ?? 0) }
        if !steps.isEmpty {
            let avg = steps.reduce(0,+) / steps.count
            line("You averaged a number of \(avg) steps/day")
        } else {
            line("You averaged a number of N/A steps/day")
        }
    }
}

// MARK: - Filename helpers

/// Format like "09Sep25" in a stable, English locale.
private func filenameDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "ddMMMyy"   // 09Sep25
    return f.string(from: d)
}

/// Convert an exclusive end date to the inclusive day for filename display.
private func inclusiveDisplayEnd(from exclusiveEnd: Date) -> Date {
    Calendar.current.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? exclusiveEnd
}

// Default suggested name for DB export
private func exportDefaultName() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd_HHmm"
    return "FitTrackDB_\(f.string(from: Date()))"
}

// MARK: - Small utilities

// Average of Int array
private extension Array where Element == Int {
    func average() -> Int? { isEmpty ? nil : self.reduce(0,+) / self.count }
}

// A trivial Document wrapper for exporting a folder URL (DB export)
struct FolderDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.folder]
    static var writableContentTypes: [UTType] = [.folder]

    let url: URL?
    init(url: URL?) { self.url = url }
    init(configuration: ReadConfiguration) throws { url = nil }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return try FileWrapper(url: url, options: .immediate)
    }
}
