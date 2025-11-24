//
//  ContentView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import SwiftData
import SwiftUI
internal import _LocationEssentials

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State var gs_deviation: Double = 0
    @EnvironmentObject var genericLocation: GenericLocation
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var airportSelection: AirportSelection
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
                            Text("ANG")
                            Text(
                                "\(genericLocation.angleToDestination, specifier: "%.1f")"
                            )
                            .foregroundColor(getLocationColor())
                            .bold()
                        }
                    }
                    .padding(.vertical, 8)

                    Group {
                        switch appSettings.visualization {
                        case .glideSlope:
                            GlideSlopeView(locationColor: getLocationColor())
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
        let databaseManager = DatabaseManager()
        if let airport = databaseManager.getAirport(ident: airportIdent) {
            airportSelection.setAirport(airport)
            navigateToAirportSelection = true
        }
    }

    // If location data is lost, purple things become yellow
    private func getLocationColor() -> Color {
        if genericLocation.locationIsStale {
            return Color(red: 0.8, green: 0.8, blue: 0)
        } else {
            return Color(red: 1, green: 0, blue: 1)
        }
    }

}
