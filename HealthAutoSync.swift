//
//  HealthAutoSync.swift
//  FitTrack
//
//  Created by Andrei Niță on 21.09.2025.
//

import Foundation
import CoreData

@MainActor
enum HealthAutoSync {

    /// Run on launch / when app becomes active.
    /// Change `daysBack` if you want a longer window.
    static func syncRecent(daysBack: Int = 30, ctx: NSManagedObjectContext) async {
        await HealthKitManager.shared.requestAuthorizationIfNeeded()

        let cal = Calendar.current
        var day = cal.startOfDay(for: Date().addingTimeInterval(-Double(daysBack) * 86400))
        let last = cal.startOfDay(for: Date())

        while day <= last {
            do {
                let (_, bm) = try ensureLog(for: day, in: ctx)
                try await fillFromHealth(for: day, bm: bm)
                try ctx.save()
            } catch {
                // Don’t crash the app if one day fails; just continue
                print("Health auto-sync failed for \(day):", error)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
    }

    // MARK: - Internals

    private static func ensureLog(for day: Date, in ctx: NSManagedObjectContext) throws -> (DailyLog, BodyMetrics) {
        let r: NSFetchRequest<DailyLog> = DailyLog.fetchRequest()
        r.predicate = NSPredicate(format: "date == %@", day as NSDate)
        r.fetchLimit = 1
        if let existing = try ctx.fetch(r).first {
            let bm = existing.bodyMetrics ?? {
                let b = BodyMetrics(context: ctx); b.log = existing; return b
            }()
            return (existing, bm)
        } else {
            let log = DailyLog(context: ctx)
            log.date = day
            let bm = BodyMetrics(context: ctx)
            bm.log = log
            return (log, bm)
        }
    }

    /// Fill BM from Health for `day` **without overwriting** user-entered values.
    private static func fillFromHealth(for day: Date, bm: BodyMetrics) async throws {
        // Sleep (only if missing)
        if (bm.sleepStart == nil || bm.sleepEnd == nil),
           let win = try await HealthKitManager.shared.mainSleepWindow(on: day) {
            if bm.sleepStart == nil { bm.sleepStart = win.start }
            if bm.sleepEnd == nil   { bm.sleepEnd   = win.end }
        }
        // Steps (only if zero)
        if bm.steps == 0 {
            let steps = try await HealthKitManager.shared.stepsTotal(on: day)
            bm.steps = Int32(steps)
        }
        // Hydration (only if zero)
        if bm.hydrationLiters == 0 {
            let liters = try await HealthKitManager.shared.waterLiters(on: day)
            if liters > 0 { bm.hydrationLiters = liters }
        }
        // Weight (only if zero)
        if bm.weightKg == 0,
           let w = try await HealthKitManager.shared.latestWeightKg(on: day),
           w > 0 {
            bm.weightKg = w
        }
    }
}
