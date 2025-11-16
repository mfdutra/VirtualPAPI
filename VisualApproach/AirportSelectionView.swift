//
//  AirportSelectionView.swift
//  VisualApproach
//
//  Created by Marlon Dutra on 11/15/25.
//

import SwiftUI

struct AirportSelectionView: View {
    @EnvironmentObject var airportSelection: AirportSelection
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [Airport] = []
    @State private var availableRunways: [Runway] = []
    @State private var isSearching = false
    
    private let databaseManager = DatabaseManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // Airport Selection Section
            VStack(alignment: .leading, spacing: 10) {
                Text("Select Airport")
                    .font(.headline)
                    .padding(.horizontal)
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by ICAO or name", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _, newValue in
                            performSearch(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Current selection display
                if let airport = airportSelection.selectedAirport {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(airport.ident)
                                .font(.title2)
                                .bold()
                            Text(airport.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            airportSelection.clear()
                            availableRunways = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            
            Divider()
            
            // Search results or runway selection
            if airportSelection.selectedAirport == nil {
                // Show search results
                if searchResults.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "airplane.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No airports found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Search for an airport")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(searchResults, id: \.ident) { airport in
                        Button(action: {
                            selectAirport(airport)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(airport.ident)
                                    .font(.headline)
                                Text(airport.name)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Elevation: \(Int(airport.elevation_ft)) ft")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                // Show runway selection
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select Runway")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    if availableRunways.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            Text("No runways available")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(availableRunways, id: \.ident) { runway in
                            Button(action: {
                                selectRunway(runway)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(runway.ident)")
                                            .font(.headline)
                                        Text("Length: \(Int(runway.length_ft)) ft")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        if runway.displaced_threshold_ft > 0 {
                                            Text("Displaced threshold: \(Int(runway.displaced_threshold_ft)) ft")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    Spacer()
                                    if let selectedRunway = airportSelection.selectedRunway,
                                       selectedRunway.ident == runway.ident {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Airport & Runway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .disabled(airportSelection.selectedRunway == nil)
            }
        }
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Debounce search for better performance
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            if query == searchText {
                let results = databaseManager.searchAirports(query: query)
                await MainActor.run {
                    searchResults = results
                }
            }
        }
    }
    
    private func selectAirport(_ airport: Airport) {
        airportSelection.setAirport(airport)
        searchText = ""
        searchResults = []
        
        // Load runways for selected airport
        let runways = databaseManager.getRunways(forAirport: airport.ident)
        availableRunways = runways
    }
    
    private func selectRunway(_ runway: Runway) {
        airportSelection.setRunway(runway)
    }
}

#Preview {
    NavigationStack {
        AirportSelectionView()
            .environmentObject(AirportSelection())
    }
}
