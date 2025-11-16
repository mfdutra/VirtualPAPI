//
//  AirportSelection.swift
//  VisualApproach
//
//  Created by Marlon Dutra on 11/15/25.
//

import SwiftUI
import Combine

class AirportSelection: ObservableObject {
    @Published var selectedAirport: Airport?
    @Published var selectedRunway: Runway?
    @Published var descentAngle: Double = 3.0
    @Published var targetElevation: Double?

    func setAirport(_ airport: Airport) {
        self.selectedAirport = airport
        // Clear runway selection when airport changes
        self.selectedRunway = nil
        // Reset descent angle to default
        self.descentAngle = 3.0
    }
    
    func setRunway(_ runway: Runway) {
        self.selectedRunway = runway
    }
    
    func setDescentAngle(_ angle: Double) {
        self.descentAngle = angle
    }
    
    func clear() {
        self.selectedAirport = nil
        self.selectedRunway = nil
        self.descentAngle = 3.0
    }
}
