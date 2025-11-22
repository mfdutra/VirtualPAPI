//
//  VirtualPAPIApp.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import CoreLocation
import SwiftData
import SwiftUI
import UIKit

@main
struct VirtualPAPIApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var genericLocation = GenericLocation()
    @StateObject private var xgpsDataReader = XGPSDataReader()
    @StateObject private var gdl90Reader = GDL90Reader()
    @StateObject private var airportSelection = AirportSelection()
    @StateObject private var locationTracker = HighFrequencyLocationTracker()
    @Environment(\.scenePhase) private var scenePhase

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

                    // Prevent screen from turning off
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onChange(of: appSettings.locationSource) { oldValue, newValue in
                    stopListenerForSource(oldValue)
                    startListenerForSource(newValue)
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Re-enable idle timer when app goes to background to save battery
                    switch newPhase {
                    case .active:
                        UIApplication.shared.isIdleTimerDisabled = true
                    case .background, .inactive:
                        UIApplication.shared.isIdleTimerDisabled = false
                    @unknown default:
                        break
                    }
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
