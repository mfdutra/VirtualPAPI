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

enum HeaderSize: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case large = "Large"
    case xLarge = "X-Large"

    var id: String { rawValue }

    var font: Font {
        switch self {
        case .normal: return .body
        case .large: return .title2
        case .xLarge: return .title
        }
    }
}

class AppSettings: ObservableObject {
    // Injectable so tests can use an isolated store instead of the shared
    // UserDefaults.standard, which parallel test suites would otherwise race on
    private let defaults: UserDefaults

    @Published var locationSource: LocationSource {
        didSet {
            defaults.set(
                locationSource.rawValue,
                forKey: "locationSource"
            )
        }
    }

    @Published var showDebugInfo: Bool {
        didSet {
            defaults.set(showDebugInfo, forKey: "showDebugInfo")
        }
    }

    @Published var visualization: VisualizationType {
        didSet {
            defaults.set(
                visualization.rawValue,
                forKey: "visualization"
            )
        }
    }

    @Published var emaAlpha: Double {
        didSet {
            defaults.set(emaAlpha, forKey: "emaAlpha")
        }
    }

    @Published var headerSize: HeaderSize {
        didSet {
            defaults.set(headerSize.rawValue, forKey: "headerSize")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate from old useXPlane boolean if needed
        if let savedSource = defaults.string(
            forKey: "locationSource"
        ),
            let source = LocationSource(rawValue: savedSource)
        {
            self.locationSource = source
        } else if defaults.object(forKey: "useXPlane") as? Bool
            == true
        {
            // Migrate old setting
            self.locationSource = .xPlane
        } else {
            self.locationSource = .internalGPS
        }

        self.showDebugInfo =
            defaults.object(forKey: "showDebugInfo") as? Bool
            ?? false

        if let savedVisualization = defaults.string(
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
            defaults.object(forKey: "emaAlpha") as? Double ?? 0.2

        self.headerSize =
            defaults.string(forKey: "headerSize")
            .flatMap(HeaderSize.init(rawValue:)) ?? .normal
    }
}
