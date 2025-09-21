//
//  BodySection.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI
import CoreData

struct BodySection: View {
    @ObservedObject var metrics: BodyMetrics

    private var durationHours: Double? {
        guard let s = metrics.sleepStart, let e = metrics.sleepEnd, e > s else { return nil }
        return e.timeIntervalSince(s) / 3600
    }
    
    var body: some View {
        Section("Body") {
            // Date pickers (same as before, using the helper from my last message)
            DatePicker("Sleep start",
                       selection: nonOptionalDateBinding($metrics.sleepStart, default: Date()),
                       displayedComponents: .hourAndMinute)

            DatePicker("Wake time",
                       selection: nonOptionalDateBinding($metrics.sleepEnd, default: Date()),
                       displayedComponents: .hourAndMinute)

            // Steps is Int32 (non-optional)
            Stepper(
                "Steps: \(Int(metrics.steps))",
                value: Binding(
                    get: { Int(metrics.steps) },
                    set: { metrics.steps = Int32($0) }
                ),
                in: 0...100_000
            )

            // Hydration & Weight are Doubles (non-optional)
            HStack {
                Text("Hydration (L)")
                Spacer()
                TextField("0.0", value: $metrics.hydrationLiters,
                          format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            HStack {
                Text("Weight (kg)")
                Spacer()
                TextField("0.0", value: $metrics.weightKg,
                          format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            Button("Save Body") {
                try? metrics.managedObjectContext?.save()
            }
        }
    }
    private func nonOptionalDateBinding(_ source: Binding<Date?>, default def: Date) -> Binding<Date> {
        Binding<Date>(
            get: { source.wrappedValue ?? def },
            set: { source.wrappedValue = $0 }
        )
    }
}

extension Binding where Value == Date? {
    init(_ source: Binding<Date?>, default def: Date) {
        self.init(get: { source.wrappedValue ?? def },
                  set: { source.wrappedValue = $0 })
    }
}
