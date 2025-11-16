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
    
    func setAirport(_ airport: Airport) {
        self.selectedAirport = airport
        // Clear runway selection when airport changes
        self.selectedRunway = nil
    }
    
    func setRunway(_ runway: Runway) {
        self.selectedRunway = runway
    }
    
    func clear() {
        self.selectedAirport = nil
        self.selectedRunway = nil
    }
}
