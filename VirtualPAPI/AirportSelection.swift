//
//  AirportSelection.swift
//  VirtualPAPI
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
    @Published var aimingPoint: Double = 500
    @Published var favoriteAirports: Set<String> = []
    
    private let favoritesKey = "favoriteAirports"
    
    init() {
        loadFavorites()
    }
    
    func isFavorite(_ airportIdent: String) -> Bool {
        favoriteAirports.contains(airportIdent)
    }
    
    func toggleFavorite(_ airportIdent: String) {
        if favoriteAirports.contains(airportIdent) {
            favoriteAirports.remove(airportIdent)
        } else {
            favoriteAirports.insert(airportIdent)
        }
        saveFavorites()
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            favoriteAirports = Set(data)
        }
    }
    
    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteAirports), forKey: favoritesKey)
    }

    func setAirport(_ airport: Airport) {
        self.selectedAirport = airport
        // Clear runway selection when airport changes
        self.selectedRunway = nil
        // Reset descent angle to default
        self.descentAngle = 3.0
    }

    func setTargets() {
        // No runway selected: nothing to aim at, leave the targets alone
        guard let runway = self.selectedRunway else { return }

        // Some runways don't have elevation information
        // Default to the airport elevation
        if runway.elevation_ft != nil {
            self.targetElevation = runway.elevation_ft
        } else {
            self.targetElevation = self.selectedAirport?.elevation_ft
        }

        // Move the target according to displacement threshold and selected aiming point
        if let aimingPoint = calculateAimingPoint() {
            (self.targetLatitude, self.targetLongitude) = aimingPoint
        }
    }

    func setRunway(_ runway: Runway) {
        self.selectedRunway = runway

        setTargets()
    }

    func setDescentAngle(angle: Double) {
        self.descentAngle = angle
    }

    func clear() {
        // Reset aimingPoint first: AirportSelectionView watches it and calls
        // setTargets() on change, so changing it after the runway is cleared
        // would recalculate the targets with no runway selected
        self.aimingPoint = 500
        self.descentAngle = 3.0
        self.selectedAirport = nil
        self.selectedRunway = nil
        self.targetElevation = nil
        self.targetLatitude = nil
        self.targetLongitude = nil
    }

    /// Calculates the final aiming point, considering the desired aiming
    /// point plus the displaced threshold of the runway
    /// - Returns: A tuple containing the latitude and longitude of the aiming
    ///   point, or nil if no runway is selected
    func calculateAimingPoint() -> (
        latitude: Double, longitude: Double
    )? {
        guard let runway = self.selectedRunway else { return nil }

        // If there's nothing to calculate, return the runway's original coordinates
        guard runway.displaced_threshold_ft > 0 || self.aimingPoint > 0 else {
            return (runway.latitude_deg, runway.longitude_deg)
        }

        // Need heading to calculate displacement direction
        guard let heading = runway.heading_degT else {
            return (runway.latitude_deg, runway.longitude_deg)
        }

        // Convert distance from feet to meters
        let distanceMeters =
            (runway.displaced_threshold_ft
                + self.aimingPoint) * 0.3048

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
