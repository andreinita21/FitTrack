//
//  HealthKitManager.swift
//  FitTrack
//
//  Created by Andrei Niță on 21.09.2025.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)! // weight
        ]
    }

    func requestAuthorizationIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            print("HK auth error:", error)
        }
    }

    // MARK: - Steps (day total)

    func stepsTotal(on day: Date) async throws -> Int {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let (start, end) = Self.dayBounds(day)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, err in
                if let err = err { return cont.resume(throwing: err) }
                let sum = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: Int(sum.rounded()))
            }
            self.store.execute(q)
        }
    }

    // MARK: - Hydration (day total)

    func waterLiters(on day: Date) async throws -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater)!
        let (start, end) = Self.dayBounds(day)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, err in
                if let err = err { return cont.resume(throwing: err) }
                let liters = stats?.sumQuantity()?.doubleValue(for: .liter()) ?? 0
                cont.resume(returning: liters)
            }
            self.store.execute(q)
        }
    }

    // MARK: - Weight (latest sample up to end-of-day)

    // Latest weight (kg) up to and including the given day’s end.
    // Pass nil to get the absolute latest regardless of date.
    func latestWeightKg(upTo day: Date?) async throws -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let end: Date? = day.map { Calendar.current.date(byAdding: .day, value: 1, to: $0.startOfDayLocal)! }
        let predicate: NSPredicate = {
            if let end { return HKQuery.predicateForSamples(withStart: nil, end: end, options: .strictEndDate) }
            return HKQuery.predicateForSamples(withStart: nil, end: nil, options: [])
        }()

        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type,
                                  predicate: predicate,
                                  limit: 1,
                                  sortDescriptors: [sort]) { _, results, err in
                if let err = err { return cont.resume(throwing: err) }
                guard let s = results?.first as? HKQuantitySample else { return cont.resume(returning: nil) }
                cont.resume(returning: s.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            self.store.execute(q)
        }
    }

    // Backward compatible shim if anything still calls the old name.
    func latestWeightKg(on day: Date) async throws -> Double? {
        try await latestWeightKg(upTo: day)
    }

    // MARK: - Sleep main window

    struct SleepWindow { let start: Date; let end: Date }

    func mainSleepWindow(on day: Date) async throws -> SleepWindow? {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        // Night window: 8pm previous day → noon current day
        let startOfDay = Calendar.current.startOfDay(for: day)
        let start = Calendar.current.date(byAdding: .hour, value: -4, to: startOfDay)! // 20:00 previous day
        let end   = Calendar.current.date(byAdding: .hour, value: 12, to: startOfDay)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, results, err in
                if let err = err { return cont.resume(throwing: err) }
                let asleep = (results as? [HKCategorySample])?
                    .filter {
                        $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                        $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    }
                    .sorted { $0.startDate < $1.startDate } ?? []
                guard let first = asleep.first, let last = asleep.last else {
                    return cont.resume(returning: nil)
                }
                cont.resume(returning: SleepWindow(start: first.startDate, end: last.endDate))
            }
            self.store.execute(q)
        }
    }

    // MARK: - Helpers

    private static func dayBounds(_ day: Date) -> (Date, Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }
}
