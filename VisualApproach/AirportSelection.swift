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
    @Published var targetLatitude: Double?
    @Published var targetLongitude: Double?

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

        // Move the target according to displacement threshold
        (self.targetLatitude, self.targetLongitude) =
            calculateDisplacedThreshold(for: runway)
    }

    func setDescentAngle(_ angle: Double) {
        self.descentAngle = angle
    }

    func clear() {
        self.selectedAirport = nil
        self.selectedRunway = nil
        self.descentAngle = 3.0
        self.targetElevation = nil
        self.targetLatitude = nil
        self.targetLongitude = nil
    }

    /// Calculates the location of the displaced threshold for a runway
    /// - Parameter runway: The runway with displacement information
    /// - Returns: A tuple containing the latitude and longitude of the displaced threshold, or nil if heading is not available
    func calculateDisplacedThreshold(for runway: Runway) -> (
        latitude: Double, longitude: Double
    ) {
        // If there's no displacement, return the runway's original coordinates
        guard runway.displaced_threshold_ft > 0 else {
            return (runway.latitude_deg, runway.longitude_deg)
        }

        // Need heading to calculate displacement direction
        guard let heading = runway.heading_degT else {
            return (runway.latitude_deg, runway.longitude_deg)
        }

        // Convert distance from feet to meters
        let distanceMeters = runway.displaced_threshold_ft * 0.3048

        // Earth's radius in meters
        let earthRadius = 6371000.0

        // Convert to radians
        let lat1 = runway.latitude_deg * .pi / 180.0
        let lon1 = runway.longitude_deg * .pi / 180.0
        let bearingRad = heading * .pi / 180.0

        // Calculate angular distance
        let angularDistance = distanceMeters / earthRadius

        // Calculate new latitude
        let lat2 = asin(
            sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance)
                * cos(bearingRad)
        )

        // Calculate new longitude
        let lon2 =
            lon1
            + atan2(
                sin(bearingRad) * sin(angularDistance) * cos(lat1),
                cos(angularDistance) - sin(lat1) * sin(lat2)
            )

        // Convert back to degrees
        let newLatitude = lat2 * 180.0 / .pi
        let newLongitude = lon2 * 180.0 / .pi

        return (newLatitude, newLongitude)
    }
}
