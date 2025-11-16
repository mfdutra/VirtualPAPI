//
//  AirportSelection.swift
//  VisualApproach
//
//  Created by Marlon Dutra on 11/15/25.
//

import Combine
import SwiftUI

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

        // Some runways don't have elevation information
        // Default to the airport elevation
        if runway.elevation_ft != nil {
            self.targetElevation = runway.elevation_ft
        } else {
            self.targetElevation = self.selectedAirport?.elevation_ft
        }
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
