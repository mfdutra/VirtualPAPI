//
//  VirtualPAPIApp.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import CoreLocation
import SwiftData
import SwiftUI

@main
struct VirtualPAPIApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var genericLocation = GenericLocation()
    @StateObject private var xgpsDataReader = XGPSDataReader()
    @StateObject private var gdl90Reader = GDL90Reader()
    @StateObject private var airportSelection = AirportSelection()
    @StateObject private var locationTracker = HighFrequencyLocationTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .environmentObject(genericLocation)
                .environmentObject(xgpsDataReader)
                .environmentObject(gdl90Reader)
                .environmentObject(airportSelection)
                .environmentObject(locationTracker)
                .onAppear {
                    xgpsDataReader.genericLocation = genericLocation
                    xgpsDataReader.appSettings = appSettings
                    gdl90Reader.genericLocation = genericLocation
                    gdl90Reader.appSettings = appSettings
                    genericLocation.airportSelection = airportSelection
                    locationTracker.appSettings = appSettings
                    locationTracker.genericLocation = genericLocation
                    locationTracker.startTracking()

                    // Start the initial location source listener
                    startListenerForSource(appSettings.locationSource)
                }
                .onChange(of: appSettings.locationSource) { oldValue, newValue in
                    stopListenerForSource(oldValue)
                    startListenerForSource(newValue)
                }
        }
    }

    private func startListenerForSource(_ source: LocationSource) {
        genericLocation.reset()
        switch source {
        case .internalGPS:
            // HighFrequencyLocationTracker is already started in onAppear
            break
        case .xPlane:
            xgpsDataReader.startListening()
        case .gdl90:
            gdl90Reader.startListening()
        }
    }

    private func stopListenerForSource(_ source: LocationSource) {
        switch source {
        case .internalGPS:
            // Don't stop HighFrequencyLocationTracker as it runs continuously
            break
        case .xPlane:
            xgpsDataReader.stopListening()
        case .gdl90:
            gdl90Reader.stopListening()
        }
    }
}
