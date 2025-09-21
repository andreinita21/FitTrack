//
//  Create UI+Keyboard.swift
//  FitTrack
//
//  Created by Andrei Niță on 21.09.2025.
//

import UIKit

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
