//
//  GenericLocation.swift
//  VNAV
//
//  Created by Marlon Dutra on 5/26/25.
//

import Foundation
import Combine

class GenericLocation: ObservableObject {
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var altitude: Double = 0
    @Published var distanceToDestination: Double = 0
    @Published var angleToDestination: Double = 0
    @Published var gsOffset: Double = 0
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
//        startDistanceCalculation()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // Update distance to destination every second
//    private func startDistanceCalculation() {
//        timer?.invalidate()
//        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
//            self?.updateDistanceToDestination()
//        }
//    }
    
//    private func updateDistanceToDestination() {
//        guard let selectedAirport = airportSelection?.selectedAirport,
//              latitude != 0 || longitude != 0 else {
//            distanceToDestination = 0
//            return
//        }
//        
//        distanceToDestination = distance(to: selectedAirport.latitude, otherLongitude: selectedAirport.longitude)
//        updateAngleToDestination(airport: selectedAirport)
//        updateGSOffset(reference: 3, actual: angleToDestination)
//    }
    
    private func updateAngleToDestination(airport: Airport) {
        let distanceInFeet = distanceToDestination * 6076.1155
        let altToLose = altitude - airport.elevation_ft
        
        angleToDestination = atan(altToLose / distanceInFeet) * 180 / .pi
    }

    private func updateGSOffset(reference: Double, actual: Double) {
        let diff = actual - reference

        // 1-dot deviation in GS is 0.15 degrees
        // Multiply by 1.11... to match the position of the dot on screen
        var deviation = diff * 1.11111111106666666666
        
        if deviation > 0.45 {
            deviation = 0.45
        }
        else if deviation < -0.45 {
            deviation = -0.45
        }
        
        gsOffset = deviation
    }

    func distance(to otherLatitude: Double, otherLongitude: Double) -> Double {
        return distance(from: self.latitude, self.longitude, to: otherLatitude, otherLongitude)
    }
    
    func distance(from lat1: Double, _ lon1: Double, to lat2: Double, _ lon2: Double) -> Double {
        // WGS84 ellipsoid parameters
        let a = 6378137.0 // Semi-major axis in meters
        let f = 1.0 / 298.257223563 // Flattening
        let b = (1.0 - f) * a // Semi-minor axis
        
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLonRad = (lon2 - lon1) * .pi / 180
        
        // Vincenty's inverse formula for ellipsoids
        let L = deltaLonRad
        let U1 = atan((1.0 - f) * tan(lat1Rad))
        let U2 = atan((1.0 - f) * tan(lat2Rad))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinU2 = sin(U2), cosU2 = cos(U2)
        
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
            sinSigma = sqrt((cosU2 * sinLambda) * (cosU2 * sinLambda) + 
                           (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda) * 
                           (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda))
            
            if sinSigma == 0 { return 0 } // Co-incident points
            
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha
            
            if cos2SigmaM.isNaN { cos2SigmaM = 0 } // Equatorial line
            
            let C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
            lambdaP = lambda
            lambda = L + (1 - C) * f * sinAlpha * 
                    (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            
            iterLimit -= 1
        } while abs(lambda - lambdaP) > 1e-12 && iterLimit > 0
        
        if iterLimit == 0 {
            // Fallback to haversine for antipodal points
            return haversineDistance(from: lat1, lon1, to: lat2, lon2)
        }
        
        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4 * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
                        B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        
        return (b * A * (sigma - deltaSigma)) / 1852 // nautical miles
    }
    
    private func haversineDistance(from lat1: Double, _ lon1: Double, to lat2: Double, _ lon2: Double) -> Double {
        let earthRadius = 6371000.0 // Earth radius in meters
        
        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLatRad = (lat2 - lat1) * .pi / 180
        let deltaLonRad = (lon2 - lon1) * .pi / 180
        
        let a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLonRad / 2) * sin(deltaLonRad / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return (earthRadius * c) / 1852 // nautical miles
    }
}
