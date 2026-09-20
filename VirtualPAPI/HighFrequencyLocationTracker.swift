//
//  HighFrequencyLocationTracker.swift
//  VNAV
//
//  Created by Claude Code on 5/23/25.
//

import Combine
import CoreLocation
import Foundation

class HighFrequencyLocationTracker: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var elevation: Double?
    @Published var accuracy: CLLocationAccuracy = 0
    @Published var verticalAccuracy: CLLocationAccuracy = 0
    @Published var groundSpeed: Double?  // in knots
    @Published var track: Double?  // course in degrees (0-360)
    @Published var isTracking = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private var isUpdatingLocation = false

    var appSettings: AppSettings?
    var genericLocation: GenericLocation?

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = locationManager.authorizationStatus
    }

    func startTracking() {
        guard
            authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .authorizedAlways
        else {
            requestLocationPermission()
            isTracking = true  // Mark as wanting to track
            return
        }

        // Idempotent: the authorization callback may call this again
        guard !isUpdatingLocation else { return }

        isTracking = true
        isUpdatingLocation = true
        // Continuous updates at the best accuracy with no distance filter.
        // Safe to call repeatedly (e.g. on authorization changes).
        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        stopLocationUpdates()
    }

    private func stopLocationUpdates() {
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }

    private func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Vertical accuracy (metres, 1 sigma) above which the altitude is too
    /// uncertain to trust for glidepath guidance. 15 m is about 0.45 degrees
    /// of angular error at 1 NM on a 3 degree path, still inside the 0.7
    /// degree full-scale deflection of the display.
    static let poorVerticalAccuracy: CLLocationAccuracy = 15

    /// True when the last accepted fix's altitude is too uncertain to trust.
    var verticalAccuracyIsPoor: Bool {
        verticalAccuracy > Self.poorVerticalAccuracy
    }

    deinit {
        stopTracking()
    }
}

extension HighFrequencyLocationTracker: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        // CoreLocation signals an invalid coordinate with a negative
        // horizontalAccuracy and an invalid altitude with a negative
        // verticalAccuracy (the altitude is then typically 0, which would
        // peg the glidepath display at "fly up"). Drop the whole fix rather
        // than feed either one to the guidance; the location then simply
        // goes stale.
        guard location.horizontalAccuracy >= 0,
            location.verticalAccuracy >= 0
        else { return }

        DispatchQueue.main.async {
            self.currentLocation = location.coordinate
            self.accuracy = location.horizontalAccuracy
            self.verticalAccuracy = location.verticalAccuracy
            self.elevation = location.altitude

            // Extract ground speed (convert m/s to knots)
            // CLLocation speed is in m/s, negative if invalid
            if location.speed >= 0 {
                self.groundSpeed = location.speed * 1.9438445  // m/s to knots
            } else {
                self.groundSpeed = nil
            }

            // Extract track (course)
            // CLLocation course is 0-360 degrees, negative if invalid
            if location.course >= 0 {
                self.track = location.course
            } else {
                self.track = nil
            }

            // Only update genericLocation if using internal GPS
            if let appSettings = self.appSettings,
                appSettings.locationSource == .internalGPS,
                let genericLocation = self.genericLocation,
                let currentLocation = self.currentLocation,
                let elevation = self.elevation
            {
                genericLocation.updateLocation(
                    latitude: currentLocation.latitude,
                    longitude: currentLocation.longitude,
                    altitude: elevation * 3.2808399,  // meter to feet
                    speed: self.groundSpeed,
                    track: self.track
                )
            }
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            self.authorizationStatus = status

            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.isTracking {
                    self.startTracking()
                }
            } else if status == .denied || status == .restricted {
                // Keep isTracking so updates resume if permission is
                // granted later (e.g. from the Settings app)
                self.stopLocationUpdates()
            }
        }
    }
}
