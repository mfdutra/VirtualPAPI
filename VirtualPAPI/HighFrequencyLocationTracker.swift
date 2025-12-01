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
    private var timer: Timer?

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var elevation: Double?
    @Published var accuracy: CLLocationAccuracy = 0
    @Published var groundSpeed: Double?  // in knots
    @Published var track: Double?  // course in degrees (0-360)
    @Published var isTracking = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var appSettings: AppSettings?
    var genericLocation: GenericLocation?

    private let updateFrequency: TimeInterval = 0.5  // 2 times per second

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

        isTracking = true
        locationManager.startUpdatingLocation()

        // Start high-frequency timer
        timer = Timer.scheduledTimer(
            withTimeInterval: updateFrequency,
            repeats: true
        ) { [weak self] _ in
            self?.requestLocationUpdate()
        }
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
    }

    private func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    private func requestLocationUpdate() {
        // Force location manager to provide updates
        locationManager.requestLocation()
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

        DispatchQueue.main.async {
            self.currentLocation = location.coordinate
            self.accuracy = location.horizontalAccuracy
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

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        DispatchQueue.main.async {
            self.authorizationStatus = status

            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.isTracking {
                    self.startTracking()
                }
            } else if status == .denied || status == .restricted {
                self.stopTracking()
            }
        }
    }
}
