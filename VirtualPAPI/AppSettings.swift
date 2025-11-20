//
//  AppSettings.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import Combine
import SwiftUI

class AppSettings: ObservableObject {
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
            UserDefaults.standard.set(favoriteAirports, forKey: "favoriteAirports")
        }
    }

    init() {
        self.useXPlane =
            UserDefaults.standard.object(forKey: "useXPlane") as? Bool ?? false
        self.showDebugInfo =
            UserDefaults.standard.object(forKey: "showDebugInfo") as? Bool
            ?? false
        self.favoriteAirports =
            UserDefaults.standard.stringArray(forKey: "favoriteAirports") ?? []
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
