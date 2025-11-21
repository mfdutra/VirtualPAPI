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
    @EnvironmentObject var xgpsDataReader: XGPSDataReader
    @EnvironmentObject var gdl90Reader: GDL90Reader
    @EnvironmentObject var airportSelection: AirportSelection
    @State private var navigateToAirportSelection = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 5) {
                if let selectedAirport = airportSelection.selectedAirport,
                    airportSelection.selectedRunway != nil
                {
                    HStack {
                        Text("DST")
                        Text(selectedAirport.ident)
                            .foregroundColor(Color(red: 1, green: 0, blue: 1))
                            .bold()
                        if let runway = airportSelection.selectedRunway {
                            Text("RWY")
                            Text(runway.ident)
                                .foregroundColor(
                                    Color(red: 1, green: 0, blue: 1)
                                )
                                .bold()
                        }
                        Text("DTG")
                        Text(
                            "\(genericLocation.distanceToDestination, specifier: "%.1f")"
                        )
                        .foregroundColor(Color(red: 1, green: 0, blue: 1))
                        .bold()
                        Text("ANG")
                        Text(
                            "\(genericLocation.angleToDestination, specifier: "%.1f")"
                        )
                        .foregroundColor(Color(red: 1, green: 0, blue: 1))
                        .bold()
                    }
                    .padding(.vertical, 8)

                    GeometryReader { geometry in
                        // Glide slope indicator
                        ZStack {
                            // Background
                            Rectangle()
                                .fill(Color(red: 0.8, green: 0.8, blue: 0.8))
                                .padding(
                                    .horizontal,
                                    geometry.size.width / 2 - 50
                                )

                            // Center line
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 100, height: 5)

                            // 3rd markers
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 40)
                                .offset(y: geometry.size.height * 0.33333)
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 40)
                                .offset(y: geometry.size.height * 0.16666)
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 40)
                                .offset(y: geometry.size.height * -0.33333)
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 40)
                                .offset(y: geometry.size.height * -0.16666)

                            // Glide path
                            Rectangle()
                                .stroke(Color.black, lineWidth: 2)
                                .background(Color(red: 1, green: 0, blue: 1))
                                .rotationEffect(Angle(degrees: 45))
                                .frame(width: 65, height: 65)
                                .opacity(0.9)
                                .offset(
                                    y: geometry.size.height
                                        * genericLocation.gsOffset
                                )
                                .animation(
                                    .linear(duration: 1),
                                    value: genericLocation.gsOffset
                                )

                            // Descent angle
                            Text(
                                "GP: \(airportSelection.descentAngle, specifier: "%.1f")°\nTDZE: \(airportSelection.targetElevation ?? 0, specifier: "%.0f")"
                            )
                            .offset(x: 130)
                            .foregroundColor(
                                Color(red: 0.6, green: 0.6, blue: 0.6)
                            )

                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Spacer()

                        Image(systemName: "airplane.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Load a destination below")
                            .foregroundColor(.secondary)
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
                        "Destination",
                        destination: AirportSelectionView()
                    )
                    .padding()
                    Spacer()
                    NavigationLink("Settings", destination: SettingsView())
                        .padding()
                }

                if appSettings.showDebugInfo {
                    Text(
                        "Lat: \(genericLocation.latitude, specifier: "%.3f") Lon: \(genericLocation.longitude, specifier: "%.3f") Alt: \(genericLocation.altitude, specifier: "%.0f")"
                    )
                    .foregroundColor(.secondary)
                }

                switch appSettings.locationSource {
                case .internalGPS:
                    Text("Using Internal GPS")
                case .xPlane:
                    Text("Using X-Plane")
                        .onAppear {
                            xgpsDataReader.startListening()
                        }
                        .onDisappear {
                            xgpsDataReader.stopListening()
                        }
                case .gdl90:
                    Text("Using GDL90")
                        .onAppear {
                            gdl90Reader.startListening()
                        }
                        .onDisappear {
                            gdl90Reader.stopListening()
                        }
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

}

#Preview {
    ContentView()
}
