//
//  AppSettings.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import Combine
import SwiftUI

enum LocationSource: String, CaseIterable, Identifiable {
    case internalGPS = "Internal GPS"
    case xPlane = "X-Plane"
    case gdl90 = "GDL90"

    var id: String { rawValue }
}

enum VisualizationType: String, CaseIterable, Identifiable {
    case glideSlope = "Glide Slope"
    case papi = "PAPI"

    var id: String { rawValue }
}

class AppSettings: ObservableObject {
    @Published var locationSource: LocationSource {
        didSet {
            UserDefaults.standard.set(
                locationSource.rawValue,
                forKey: "locationSource"
            )
        }
    }

    @Published var useXPlane: Bool {
        didSet {
            UserDefaults.standard.set(useXPlane, forKey: "useXPlane")
        }
    }

    @Published var showDebugInfo: Bool {
        didSet {
            UserDefaults.standard.set(showDebugInfo, forKey: "showDebugInfo")
        }
    }

    @Published var favoriteAirports: [String] {
        didSet {
            UserDefaults.standard.set(
                favoriteAirports,
                forKey: "favoriteAirports"
            )
        }
    }

    @Published var visualization: VisualizationType {
        didSet {
            UserDefaults.standard.set(
                visualization.rawValue,
                forKey: "visualization"
            )
        }
    }

    @Published var emaAlpha: Double {
        didSet {
            UserDefaults.standard.set(emaAlpha, forKey: "emaAlpha")
        }
    }

    init() {
        // Migrate from old useXPlane boolean if needed
        if let savedSource = UserDefaults.standard.string(
            forKey: "locationSource"
        ),
            let source = LocationSource(rawValue: savedSource)
        {
            self.locationSource = source
        } else if UserDefaults.standard.object(forKey: "useXPlane") as? Bool
            == true
        {
            // Migrate old setting
            self.locationSource = .xPlane
        } else {
            self.locationSource = .internalGPS
        }

        self.useXPlane =
            UserDefaults.standard.object(forKey: "useXPlane") as? Bool ?? false
        self.showDebugInfo =
            UserDefaults.standard.object(forKey: "showDebugInfo") as? Bool
            ?? false
        self.favoriteAirports =
            UserDefaults.standard.stringArray(forKey: "favoriteAirports") ?? []

        if let savedVisualization = UserDefaults.standard.string(
            forKey: "visualization"
        ),
            let visualizationType = VisualizationType(
                rawValue: savedVisualization
            )
        {
            self.visualization = visualizationType
        } else {
            self.visualization = .glideSlope
        }

        self.emaAlpha =
            UserDefaults.standard.object(forKey: "emaAlpha") as? Double ?? 0.2
    }

    // MARK: - Favorite Airports Management

    func addFavoriteAirport(_ airportCode: String) {
        let code = airportCode.uppercased().trimmingCharacters(in: .whitespaces)
        if !code.isEmpty && !favoriteAirports.contains(code) {
            favoriteAirports.append(code)
        }
    }

    func removeFavoriteAirport(_ airportCode: String) {
        favoriteAirports.removeAll { $0 == airportCode }
    }

    func isFavorite(_ airportCode: String) -> Bool {
        favoriteAirports.contains(airportCode.uppercased())
    }

    func toggleFavorite(_ airportCode: String) {
        let code = airportCode.uppercased().trimmingCharacters(in: .whitespaces)
        if isFavorite(code) {
            removeFavoriteAirport(code)
        } else {
            addFavoriteAirport(code)
        }
    }
}
