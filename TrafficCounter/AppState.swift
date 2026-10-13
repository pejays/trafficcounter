//
//  AppState.swift
//  TrafficCounter
//
//  Created by Jhon Patrick Acedo on 5/26/26.
//


//
//  AppState.swift
//  TrafficCounter
//

import Foundation
import SwiftUI
import Combine

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var isCameraEnabled = true
    @Published var isSessionActive = false
    @Published var vehicleCounts: [String: Int] = [
        "Private Car": 0,
        "Motorcycle": 0,
        "Jeepney": 0,
        "Bus/Minibus": 0,
        "Light Truck": 0,
        "Heavy Truck": 0,
        "Tricycle": 0,
        "UV": 0
    ]
}
