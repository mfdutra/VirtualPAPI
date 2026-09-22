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
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published private(set) var isUpdatingLocation = false

    // Diagnostics for InternalLocationDebugView
    /// Every fix CoreLocation delivers, including ones dropped as invalid
    @Published private(set) var lastRawLocation: CLLocation?
    @Published private(set) var lastRejectionReason: String?
    @Published private(set) var acceptedFixCount = 0
    @Published private(set) var rejectedFixCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastErrorTime: Date?
    @Published private(set) var updatesPaused = false
    @Published private(set) var heading: CLHeading?
    @Published private(set) var isUpdatingHeading = false
    @Published private(set) var locationServicesEnabled: Bool?

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
        // Aircraft use: .airborne disables the ground-vehicle filtering
        // (e.g. snapping to roads), and automatic pausing must stay off.
        // With pausing on, CoreLocation stops delivering fixes once it
        // decides the device is stationary (a long hold short or run-up)
        // and doesn't resume them on its own, so the display would go
        // stale on the take-off roll.
        locationManager.activityType = .airborne
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
        accuracyAuthorization = locationManager.accuracyAuthorization
    }

    // Read-only view of the manager's configuration, for diagnostics
    var desiredAccuracy: CLLocationAccuracy { locationManager.desiredAccuracy }
    var distanceFilter: CLLocationDistance { locationManager.distanceFilter }
    var activityType: CLActivityType { locationManager.activityType }
    var pausesLocationUpdatesAutomatically: Bool {
        locationManager.pausesLocationUpdatesAutomatically
    }
    var headingFilter: CLLocationDegrees { locationManager.headingFilter }

    /// Refresh the system-wide Location Services switch. The class method
    /// can block, so it's queried off the main thread.
    func refreshLocationServicesEnabled() {
        Task {
            let enabled = await Task.detached {
                CLLocationManager.locationServicesEnabled()
            }.value
            self.locationServicesEnabled = enabled
        }
    }

    /// Heading is diagnostics only (the guidance uses GPS track), so it runs
    /// only while the debug view is on screen.
    func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable(), !isUpdatingHeading else {
            return
        }
        isUpdatingHeading = true
        locationManager.startUpdatingHeading()
    }

    func stopHeadingUpdates() {
        guard isUpdatingHeading else { return }
        isUpdatingHeading = false
        locationManager.stopUpdatingHeading()
    }

    /// Why a fix can't be used, or nil if it can. CoreLocation signals an
    /// invalid coordinate with a negative horizontalAccuracy and an invalid
    /// altitude with a negative verticalAccuracy.
    ///
    /// Simulated fixes skip both checks: the Simulator (and Xcode location
    /// simulation) always reports verticalAccuracy -1 with altitude 0, so
    /// they would otherwise all be dropped and internal GPS couldn't be
    /// exercised there at all.
    static func rejectionReason(
        horizontalAccuracy: CLLocationAccuracy,
        verticalAccuracy: CLLocationAccuracy,
        isSimulatedBySoftware: Bool = false
    ) -> String? {
        if isSimulatedBySoftware {
            return nil
        }
        if horizontalAccuracy < 0 {
            return "Invalid coordinate (horizontal accuracy < 0)"
        }
        if verticalAccuracy < 0 {
            return "Invalid altitude (vertical accuracy < 0)"
        }
        return nil
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
        // goes stale. Simulated fixes are exempt (see rejectionReason).
        lastRawLocation = location
        lastRejectionReason = Self.rejectionReason(
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            isSimulatedBySoftware: location.sourceInformation?
                .isSimulatedBySoftware ?? false
        )
        guard lastRejectionReason == nil else {
            rejectedFixCount += 1
            return
        }
        acceptedFixCount += 1

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
        lastError = Self.describe(error)
        lastErrorTime = Date()
    }

    /// Name the CLError code, since its localizedDescription is just
    /// "kCLErrorDomain error N"
    static func describe(_ error: Error) -> String {
        guard let clError = error as? CLError else {
            return error.localizedDescription
        }
        let name: String
        switch clError.code {
        case .locationUnknown: name = "locationUnknown (no fix yet)"
        case .denied: name = "denied"
        case .network: name = "network"
        case .headingFailure: name = "headingFailure"
        case .promptDeclined: name = "promptDeclined"
        default: name = "code \(clError.code.rawValue)"
        }
        return "kCLError \(clError.code.rawValue): \(name)"
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        heading = newHeading
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        updatesPaused = true
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        updatesPaused = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.accuracyAuthorization = accuracy
            self.refreshLocationServicesEnabled()

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
