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

    init() {
        self.useXPlane =
            UserDefaults.standard.object(forKey: "useXPlane") as? Bool ?? false
        self.showDebugInfo =
            UserDefaults.standard.object(forKey: "showDebugInfo") as? Bool
            ?? false
    }
}
