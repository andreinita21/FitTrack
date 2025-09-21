//
//  AddMealView.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import SwiftUI

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    let defaultDate: Date

    @State private var type = "Breakfast"
    @State private var time: Date
    @State private var location = ""
    @State private var desc = ""

    let onSave: (String, Date, String?, String?) -> Void

    init(defaultDate: Date, onSave: @escaping (String, Date, String?, String?) -> Void) {
        self.defaultDate = defaultDate
        self.onSave = onSave
        _time = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    Text("Breakfast").tag("Breakfast")
                    Text("Lunch").tag("Lunch")
                    Text("Dinner").tag("Dinner")
                    Text("Snack").tag("Snack")
                }
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                TextField("Location", text: $location)
                TextField("Description", text: $desc, axis: .vertical)
            }
            .navigationTitle("New Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(type, time, location.isEmpty ? nil : location, desc.isEmpty ? nil : desc)
                        dismiss()
                    }
                }
            }
        }
    }
}
