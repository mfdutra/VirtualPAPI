//
//  VisualApproachApp.swift
//  VisualApproach
//
//  Created by Marlon Dutra on 11/15/25.
//

import SwiftUI
import SwiftData

@main
struct VisualApproachApp: App {
//    var sharedModelContainer: ModelContainer = {
//        let schema = Schema([
//            Item.self,
//        ])
//        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//
//        do {
//            return try ModelContainer(for: schema, configurations: [modelConfiguration])
//        } catch {
//            fatalError("Could not create ModelContainer: \(error)")
//        }
//    }()

    @StateObject private var appSettings = AppSettings()
    @StateObject private var genericLocation = GenericLocation()
    @StateObject private var xgpsDataReader = XGPSDataReader()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
                .environmentObject(genericLocation)
                .environmentObject(xgpsDataReader)        }
//                .onAppear {
//            xgpsDataReader.genericLocation = genericLocation
//        }
    }
}
