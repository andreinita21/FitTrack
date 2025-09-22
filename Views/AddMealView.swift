//
//  AddMealView.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI

struct AddMealView: View {
    // Inputs
    let defaultDate: Date
    let onSave: (_ type: String, _ time: Date, _ location: String?, _ desc: String?) -> Void

    // UI
    @Environment(\.dismiss) private var dismiss
    @State private var timestamp: Date = Date()
    @State private var type: String = "Snack"
    @State private var location: String = ""
    @State private var desc: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // WHEN: only time picker
                Section("When") {
                    DatePicker("Time",
                               selection: $timestamp,
                               displayedComponents: [.hourAndMinute])
                        .onChange(of: timestamp) { _, newValue in
                            type = suggestedType(for: newValue)
                        }
                }

                // MEAL TYPE: slider-style segmented control
                Section("Meal Type") {
                    MealTypeSelector(selected: $type)  // no 'items:' needed
                        .frame(height: 40)
                }

                // DETAILS
                Section("Details") {
                    TextField("Location", text: $location)
                        .textInputAutocapitalization(.words)

                    TextField("What did you eat?", text: $desc, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Add Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            type,
                            timestamp,
                            location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
                            desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : desc
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                timestamp = combine(date: defaultDate, withTimeOf: Date())
                type = suggestedType(for: timestamp)
            }
        }
    }

    // MARK: - Helpers

    private func suggestedType(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5...10:  return "Breakfast"
        case 11...15: return "Lunch"
        case 18...22: return "Dinner"
        default:      return "Snack"
        }
    }

    private func combine(date day: Date, withTimeOf timeSource: Date) -> Date {
        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: day)
        let tc = cal.dateComponents([.hour, .minute], from: timeSource)
        dc.hour = tc.hour
        dc.minute = tc.minute
        return cal.date(from: dc) ?? day
    }
}

// MARK: - Slider-style segmented control (nested)

extension AddMealView {
    struct MealTypeSelector: View {
        @Binding var selected: String
        private let items: [String] = ["Breakfast", "Lunch", "Dinner", "Snack"]

        private func color(for type: String) -> Color {
            switch type {
            case "Breakfast": return .yellow
            case "Lunch":     return .green
            case "Dinner":    return .blue
            default:          return .red // Snack
            }
        }

        var body: some View {
            GeometryReader { geo in
                let count = CGFloat(items.count)
                let segmentW = geo.size.width / max(count, 1)
                let trackH: CGFloat = 40
                let pillInset: CGFloat = 2   // make pill bigger by reducing inset

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: trackH/2)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: trackH/2)
                                .stroke(.secondary.opacity(0.25), lineWidth: 1)
                        )

                    // Sliding pill (bigger than before)
                    RoundedRectangle(cornerRadius: (trackH/2) - pillInset)
                        .fill(color(for: selected).opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: (trackH/2) - pillInset)
                                .stroke(.primary.opacity(0.15), lineWidth: 1)
                        )
                        .frame(width: segmentW - pillInset, height: trackH - pillInset*1.5)
                        .offset(x: segmentW * CGFloat(index(of: selected)) + pillInset/2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: selected)

                    // Labels
                    HStack(spacing: 0) {
                        ForEach(items, id: \.self) { item in
                            Text(item)
                                .font(.system(size: 14, weight: .semibold)) // fits all text
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(width: segmentW, height: trackH)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = item }
                        }
                    }
                }
                .frame(height: trackH)
            }
            .frame(height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }

        private func index(of item: String) -> Int {
            items.firstIndex(of: item) ?? 0
        }
    }
}
