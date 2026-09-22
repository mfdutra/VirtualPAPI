//
//  ContentView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import SwiftUI

struct ContentView: View {
    @State var gs_deviation: Double = 0
    @EnvironmentObject var genericLocation: GenericLocation
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var airportSelection: AirportSelection
    @EnvironmentObject var gdl90Reader: GDL90Reader
    @EnvironmentObject var locationTracker: HighFrequencyLocationTracker
    @State private var navigateToAirportSelection = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 5) {
                if let selectedAirport = airportSelection.selectedAirport,
                    let selectedRunway = airportSelection.selectedRunway
                {
                    VStack {
                        HStack {
                            Text(
                                "\(selectedAirport.ident) \(selectedRunway.ident)"
                            )
                            .font(.title2)
                            if let bearing = genericLocation
                                .relativeBearingToDestination,
                                !genericLocation.locationIsStale
                            {
                                Image(systemName: "arrow.up")
                                    .font(.title2)
                                    .rotationEffect(Angle(degrees: bearing))
                                    .animation(
                                        .linear(duration: 1),
                                        value: bearing
                                    )
                            }
                        }
                        HStack {
                            Text("DTG")
                            Text(
                                "\(genericLocation.distanceToDestination, specifier: "%.1f")"
                            )
                            .foregroundColor(getLocationColor())
                            .bold()
                            Text("V/B")
                            Text(
                                "\(genericLocation.angleToDestination, specifier: "%.1f")"
                            )
                            .foregroundColor(getLocationColor())
                            .bold()
                            Text("V/S")
                            Text(
                                ContentView.formatVerticalSpeed(
                                    genericLocation.verticalSpeedToDestination
                                )
                            )
                                .foregroundColor(getLocationColor())
                                .bold()
                        }
                        .font(appSettings.headerSize.font)

                        // Internal GPS and X-Plane are always MSL; GDL90 may
                        // fall back to pressure altitude
                        if usingPressureAltitude {
                            Label(
                                "PRESS ALT",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }

                        // A phone's GPS altitude can be uncertain by more
                        // than the full-scale deflection of the display
                        if appSettings.locationSource == .internalGPS,
                            !genericLocation.locationIsStale,
                            locationTracker.verticalAccuracyIsPoor
                        {
                            Label(
                                ContentView.formatVerticalAccuracy(
                                    locationTracker.verticalAccuracy
                                ),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 8)

                    Group {
                        switch appSettings.visualization {
                        case .glideSlope:
                            GlideSlopeView(
                                locationColor: ContentView.diamondColor(
                                    locationIsStale: genericLocation
                                        .locationIsStale,
                                    usingPressureAltitude: usingPressureAltitude
                                )
                            )
                        case .papi:
                            PapiView()
                        }
                    }
                    .onTapGesture(count: 2) {
                        appSettings.visualization =
                            appSettings.visualization == .glideSlope
                            ? .papi : .glideSlope
                    }
                } else {
                    VStack(spacing: 10) {
                        Spacer()

                        NavigationLink(
                            destination: AirportSelectionView()
                        ) {
                            VStack {
                                Image(systemName: "airplane.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("Load a destination")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 5)
                            }

                        }
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                            .padding(.top, 30)
                        Text("USE IN VISUAL CONDITIONS ONLY")
                            .foregroundColor(.red)
                            .bold()

                        Spacer()

                        // Favorite Airports Section
                        if !airportSelection.favoriteAirports.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Favorite Airports")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ScrollView(.horizontal, showsIndicators: false)
                                {
                                    HStack(spacing: 12) {
                                        ForEach(
                                            airportSelection.favoriteAirports
                                                .sorted(),
                                            id: \.self
                                        ) { airportIdent in
                                            Button(action: {
                                                loadFavoriteAirport(
                                                    airportIdent
                                                )
                                            }) {
                                                VStack(spacing: 4) {
                                                    Image(
                                                        systemName: "star.fill"
                                                    )
                                                    .foregroundColor(.yellow)
                                                    Text(airportIdent)
                                                        .font(.headline)
                                                        .foregroundColor(
                                                            .primary
                                                        )
                                                }
                                                .frame(width: 80, height: 80)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(10)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    NavigationLink(
                        "🔎 Destination",
                        destination: AirportSelectionView()
                    )
                    .padding()
                    Spacer()
                    NavigationLink("⚙️ Settings", destination: SettingsView())
                        .padding()
                }

                if appSettings.showDebugInfo {
                    Text(
                        "Lat: \(genericLocation.latitude, specifier: "%.3f") Lon: \(genericLocation.longitude, specifier: "%.3f") Alt: \(genericLocation.altitude, specifier: "%.0f") GS: \(genericLocation.groundSpeed ?? 0, specifier: "%.0f") TRK: \(genericLocation.track ?? 0, specifier: "%.0f")"
                    )
                    .foregroundColor(.secondary)

                    switch appSettings.locationSource {
                    case .internalGPS:
                        Text("Using Internal GPS")
                            .foregroundColor(.secondary)
                    case .xPlane:
                        Text("Using X-Plane")
                            .foregroundColor(.secondary)
                    case .gdl90:
                        Text("Using GDL90")
                            .foregroundColor(.secondary)
                    }
                }

                if genericLocation.locationIsStale {
                    Text("⚠️ Not getting location data ⚠️")
                        .foregroundColor(.red)
                        .bold()
                }
            }
            .navigationDestination(isPresented: $navigateToAirportSelection) {
                AirportSelectionView()
            }
        }
    }

    private func loadFavoriteAirport(_ airportIdent: String) {
        let databaseManager = DatabaseManager.shared
        if let airport = databaseManager.getAirport(ident: airportIdent) {
            airportSelection.setAirport(airport)
            navigateToAirportSelection = true
        }
    }

    // Required V/S in ft/min (positive = descent), rounded to the nearest 10
    static func formatVerticalSpeed(_ verticalSpeed: Double?) -> String {
        guard let vs = verticalSpeed else {
            return "---"
        }
        // Adding 0 turns -0 into 0 so it doesn't display as "-0"
        return String(format: "%.0f", (vs / 10).rounded() * 10 + 0)
    }

    // Caution text for an uncertain GPS altitude, e.g. "GPS ALT \u{00B1}70 ft"
    static func formatVerticalAccuracy(_ verticalAccuracy: Double) -> String {
        let feet = (verticalAccuracy * 3.2808399 / 10).rounded() * 10
        return String(format: "GPS ALT \u{00B1}%.0f ft", feet)
    }

    static let normalLocationColor = Color(red: 1, green: 0, blue: 1)
    static let staleLocationColor = Color(red: 0.8, green: 0.8, blue: 0)
    static let uncertainAltitudeColor = Color.orange

    // True when GDL90 is feeding pressure altitude (29.92 inHg), which can be
    // hundreds of feet off MSL on a non-standard day
    static func isUsingPressureAltitude(
        locationSource: LocationSource,
        locationIsStale: Bool,
        usingGeometricAltitude: Bool
    ) -> Bool {
        locationSource == .gdl90 && !locationIsStale && !usingGeometricAltitude
    }

    // The diamond turns amber on pressure altitude, so the pilot sees the
    // caution on the indicator itself, not only in the header caption
    static func diamondColor(
        locationIsStale: Bool,
        usingPressureAltitude: Bool
    ) -> Color {
        if locationIsStale {
            return staleLocationColor
        } else if usingPressureAltitude {
            return uncertainAltitudeColor
        } else {
            return normalLocationColor
        }
    }

    private var usingPressureAltitude: Bool {
        ContentView.isUsingPressureAltitude(
            locationSource: appSettings.locationSource,
            locationIsStale: genericLocation.locationIsStale,
            usingGeometricAltitude: gdl90Reader.usingGeometricAltitude
        )
    }

    // If location data is lost, purple things become yellow
    private func getLocationColor() -> Color {
        genericLocation.locationIsStale
            ? ContentView.staleLocationColor : ContentView.normalLocationColor
    }

}
