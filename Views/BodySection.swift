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
    @FocusState private var stepsFieldFocused: Bool

    var body: some View {
        Section("Body") {
            // Sleep
            DatePicker("Sleep start",
                       selection: nonOptionalDateBinding($metrics.sleepStart, default: Date()),
                       displayedComponents: .hourAndMinute)

            DatePicker("Wake time",
                       selection: nonOptionalDateBinding($metrics.sleepEnd, default: Date()),
                       displayedComponents: .hourAndMinute)

            // Steps (manual + quick adjust)
            HStack {
                Text("Steps:")
                Spacer()
                TextField("0", value: Binding(
                    get: { Int(metrics.steps) },
                    set: { metrics.steps = Int32($0) }
                ), format: .number)
                    .keyboardType(.numberPad)
                    .focused($stepsFieldFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)

                Button("-") {
                    if metrics.steps > 0 {
                        metrics.steps = max(0, metrics.steps - 100)
                    }
                }
                .buttonStyle(.bordered)

                Button("+") {
                    metrics.steps += 100
                }
                .buttonStyle(.bordered)
            }

            // Save button
            Button("Save Body") {
                try? metrics.managedObjectContext?.save()
                stepsFieldFocused = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // Helper to bind Date? to Date
    private func nonOptionalDateBinding(_ source: Binding<Date?>, default def: Date) -> Binding<Date> {
        Binding<Date>(
            get: { source.wrappedValue ?? def },
            set: { source.wrappedValue = $0 })
    }
}

extension Binding where Value == Date? {
    init(_ source: Binding<Date?>, default def: Date) {
        self.init(get: { source.wrappedValue ?? def },
                  set: { source.wrappedValue = $0 })
    }
}
