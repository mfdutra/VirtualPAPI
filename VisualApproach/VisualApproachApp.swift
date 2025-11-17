//
//  VisualApproachApp.swift
//  VisualApproach
//
//  Created by Marlon Dutra on 11/15/25.
//

import CoreLocation
import SwiftData
import SwiftUI

@main
struct VisualApproachApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var genericLocation = GenericLocation()
    @StateObject private var xgpsDataReader = XGPSDataReader()
    @StateObject private var airportSelection = AirportSelection()
    @StateObject private var locationTracker = HighFrequencyLocationTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .environmentObject(genericLocation)
                .environmentObject(xgpsDataReader)
                .environmentObject(airportSelection)
                .environmentObject(locationTracker)
                .onAppear {
                    xgpsDataReader.genericLocation = genericLocation
                    xgpsDataReader.appSettings = appSettings
                    genericLocation.airportSelection = airportSelection
                    locationTracker.appSettings = appSettings
                    locationTracker.genericLocation = genericLocation
                    locationTracker.startTracking()
                }
        }
    }
}
