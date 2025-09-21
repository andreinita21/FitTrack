//
//  Date+Helpers.swift
//  FitTrack
//
//  Created by Andrei Niță on 20.09.2025.
//

import Foundation
extension Date {
    var startOfDayLocal: Date { Calendar.current.startOfDay(for: self) }
    func nextDay() -> Date { Calendar.current.date(byAdding: .day, value: 1, to: startOfDayLocal)! }
}
