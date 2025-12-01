//
//  GenericLocation.swift
//  VNAV
//
//  Created by Marlon Dutra on 5/26/25.
//

import Combine
import Foundation

class GenericLocation: ObservableObject {
    @Published var altitude: Double = 0
    @Published var angleDeviation: Double = 0
    @Published var angleToDestination: Double = 0
    @Published var bearingToDestination: Double?
    @Published var distanceToDestination: Double = 0
    @Published var groundSpeed: Double?
    @Published var gsOffset: Double = 0
    @Published var lastUpdateTime: Date?
    @Published var latitude: Double = 0
    @Published var locationIsStale: Bool = false
    @Published var longitude: Double = 0
    @Published var papiColors: [Double] = [0, 0, 0, 0]
    @Published var papiPosition: Double = 0.5  // 2-reds 2-whites
    @Published var relativeBearingToDestination: Double?
    @Published var track: Double?

    private var timer: Timer?
    private var stalenessTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    var airportSelection: AirportSelection? {
        didSet {
            startDistanceCalculation()
        }
    }

    init() {
        startDistanceCalculation()
        startStalenessCheck()
    }

    deinit {
        timer?.invalidate()
        stalenessTimer?.invalidate()
    }

    func reset() {
        self.latitude = 0
        self.longitude = 0
        self.altitude = 0
        self.distanceToDestination = 0
        self.angleToDestination = 0
        self.gsOffset = 0
        self.locationIsStale = true
        self.lastUpdateTime = nil
        self.papiPosition = 0.5
        self.papiColors = [0, 0, 0, 0]
        self.groundSpeed = nil
        self.bearingToDestination = nil
        self.relativeBearingToDestination = nil
    }

    /// Update the current location coordinates
    /// - Parameters:
    ///   - latitude: Latitude in degrees
    ///   - longitude: Longitude in degrees
    ///   - altitude: Altitude in feet
    func updateLocation(latitude: Double, longitude: Double, altitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.lastUpdateTime = Date()
        self.locationIsStale = false
    }

    /// Update the current location coordinates with speed and track
    /// - Parameters:
    ///   - latitude: Latitude in degrees
    ///   - longitude: Longitude in degrees
    ///   - altitude: Altitude in feet
    ///   - speed: Ground speed in knots (nil if invalid)
    ///   - track: Track/course in degrees 0-360 (nil if invalid)
    func updateLocation(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        speed: Double?,
        track: Double?
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.groundSpeed = speed
        self.track = track
        self.lastUpdateTime = Date()
        self.locationIsStale = false
    }

    /// Calculate the heading (bearing) from one point to another
    /// - Parameters:
    ///   - lat1: Starting latitude in degrees
    ///   - lon1: Starting longitude in degrees
    ///   - lat2: Ending latitude in degrees
    ///   - lon2: Ending longitude in degrees
    /// - Returns: Heading in degrees (0-360), where 0 is North, 90 is East, etc.
    func heading(
        from lat1: Double,
        _ lon1: Double,
        to lat2: Double,
        _ lon2: Double
    ) -> Double {
        // Convert to radians
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLonRad = (lon2 - lon1) * .pi / 180

        // Calculate bearing using forward azimuth formula
        let y = sin(deltaLonRad) * cos(lat2Rad)
        let x =
            cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad)
            * cos(deltaLonRad)

        var heading = atan2(y, x) * 180 / .pi

        // Normalize to 0-360 degrees
        if heading < 0 {
            heading += 360
        }

        return heading
    }

    // Check location staleness every 5 seconds
    private func startStalenessCheck() {
        stalenessTimer?.invalidate()
        stalenessTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
        ) {
            [weak self] _ in
            self?.checkStaleness()
        }
    }

    private func checkStaleness() {
        guard let lastUpdate = lastUpdateTime else {
            // No update yet, mark as stale
            self.locationIsStale = true
            return
        }

        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
        if timeSinceLastUpdate > 5.0 {
            self.locationIsStale = true
        }
    }

    // Update location information every second
    private func startDistanceCalculation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.updateLocationInfo()
        }
    }

    private func updateLocationInfo() {
        // Skip if no airport/runway has been selected yet
        guard let airport = self.airportSelection else { return }

        guard
            (airport.targetLatitude != nil) && (airport.targetLongitude != nil)
                && (airport.targetElevation != nil)
        else { return }

        self.distanceToDestination = distance(
            otherLatitude: airport.targetLatitude!,
            otherLongitude: airport.targetLongitude!
        )
        updateAngleToDestination()
        updateBearingToDestination()
        updateGSOffset()
        updatePapiPosition()
    }

    private func updateBearingToDestination() {
        self.bearingToDestination = heading(
            from: latitude,
            longitude,
            to: airportSelection!.targetLatitude!,
            airportSelection!.targetLongitude!
        )

        // Calculate relative bearing (where destination is relative to current track)
        if let currentTrack = self.track,
            let bearing = self.bearingToDestination
        {
            var relativeBearing = bearing - currentTrack

            // Normalize to -180 to +180 range
            // Positive means turn right, negative means turn left
            if relativeBearing > 180 {
                relativeBearing -= 360
            } else if relativeBearing < -180 {
                relativeBearing += 360
            }

            self.relativeBearingToDestination = relativeBearing
        } else {
            self.relativeBearingToDestination = nil
        }
    }

    private func updateAngleToDestination() {
        let distanceInFeet = self.distanceToDestination * 6076.1155
        let altToLose = altitude - (self.airportSelection?.targetElevation)!

        self.angleToDestination = atan(altToLose / distanceInFeet) * 180 / .pi
        self.angleDeviation =
            self.angleToDestination - airportSelection!.descentAngle
    }

    private func updateGSOffset() {
        // Full scale deviation is 0.7 degrees
        // The GP indicator can only go up or down 45% of the screen
        // Divide the actual difference by 1.55 to move the
        // GP indicator in the correct proportion
        var deviation = self.angleDeviation / 1.55555555555555555555

        // Peg GP to top or bottom on the limits
        if deviation > 0.45 {
            deviation = 0.45
        } else if deviation < -0.45 {
            deviation = -0.45
        }

        self.gsOffset = deviation
    }

    private func updatePapiPosition() {
        // The PAPI is in the middle (0.5) when the angle deviation is 0,
        // so shift +0.7 (max deflection)
        //
        // The PAPI position shifts ±0.5 while the deviation shifts ±0.7,
        // so a factor of 1.4
        self.papiPosition = max(0, min(1, (self.angleDeviation + 0.7) / 1.4))
        self.papiColors = [
            max(0, min(1, (self.papiPosition - 0.75) * 4)),
            max(0, min(1, (self.papiPosition - 0.5) * 4)),
            max(0, min(1, (self.papiPosition - 0.25) * 4)),
            max(0, min(1, self.papiPosition * 4)),
        ]
    }

    func distance(otherLatitude: Double, otherLongitude: Double) -> Double {
        return distance(
            from: self.latitude,
            self.longitude,
            to: otherLatitude,
            otherLongitude
        )
    }

    /// Calculate the distance between two points on Earth, using WGS84 Earth model
    /// - Returns: distance in nautical miles
    func distance(
        from lat1: Double,
        _ lon1: Double,
        to lat2: Double,
        _ lon2: Double
    ) -> Double {
        // WGS84 ellipsoid parameters
        let a = 6378137.0  // Semi-major axis in meters
        let f = 1.0 / 298.257223563  // Flattening
        let b = (1.0 - f) * a  // Semi-minor axis

        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLonRad = (lon2 - lon1) * .pi / 180

        // Vincenty's inverse formula for ellipsoids
        let L = deltaLonRad
        let U1 = atan((1.0 - f) * tan(lat1Rad))
        let U2 = atan((1.0 - f) * tan(lat2Rad))
        let sinU1 = sin(U1)
        let cosU1 = cos(U1)
        let sinU2 = sin(U2)
        let cosU2 = cos(U2)

        var lambda = L
        var lambdaP: Double
        var iterLimit = 100
        var cosSqAlpha: Double
        var sinSigma: Double
        var cosSigma: Double
        var sigma: Double
        var cos2SigmaM: Double

        repeat {
            let sinLambda = sin(lambda)
            let cosLambda = cos(lambda)
            sinSigma = sqrt(
                (cosU2 * sinLambda) * (cosU2 * sinLambda)
                    + (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
                    * (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
            )

            if sinSigma == 0 { return 0 }  // Co-incident points

            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha

            if cos2SigmaM.isNaN { cos2SigmaM = 0 }  // Equatorial line

            let C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
            lambdaP = lambda
            lambda =
                L + (1 - C) * f * sinAlpha
                * (sigma + C * sinSigma
                    * (cos2SigmaM + C * cosSigma
                        * (-1 + 2 * cos2SigmaM * cos2SigmaM)))

            iterLimit -= 1
        } while abs(lambda - lambdaP) > 1e-12 && iterLimit > 0

        if iterLimit == 0 {
            // Fallback to haversine for antipodal points
            return haversineDistance(from: lat1, lon1, to: lat2, lon2)
        }

        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A =
            1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma =
            B * sinSigma
            * (cos2SigmaM + B / 4
                * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) - B / 6
                    * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma)
                    * (-3 + 4 * cos2SigmaM * cos2SigmaM)))

        return (b * A * (sigma - deltaSigma)) / 1852  // nautical miles
    }

    /// Calculate the approximate distance between two points on Earth,
    /// as if the planet was perfectly spherical
    /// - Returns: distance in nautical miles
    private func haversineDistance(
        from lat1: Double,
        _ lon1: Double,
        to lat2: Double,
        _ lon2: Double
    ) -> Double {
        let earthRadius = 6371000.0  // Earth radius in meters

        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLatRad = (lat2 - lat1) * .pi / 180
        let deltaLonRad = (lon2 - lon1) * .pi / 180

        let a =
            sin(deltaLatRad / 2) * sin(deltaLatRad / 2) + cos(lat1Rad)
            * cos(lat2Rad) * sin(deltaLonRad / 2) * sin(deltaLonRad / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return (earthRadius * c) / 1852  // nautical miles
    }
}
