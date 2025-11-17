//
//  VisualApproachApp.swift
//  VisualApproach
//
//  Created by Marlon Dutra on 11/15/25.
//

import SwiftData
import SwiftUI

@main
struct VisualApproachApp: App {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var genericLocation = GenericLocation()
    @StateObject private var xgpsDataReader = XGPSDataReader()
    @StateObject private var airportSelection = AirportSelection()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .environmentObject(genericLocation)
                .environmentObject(xgpsDataReader)
                .environmentObject(airportSelection)
                .onAppear {
                    xgpsDataReader.genericLocation = genericLocation
                    genericLocation.airportSelection = airportSelection
                }
        }
    }
}
