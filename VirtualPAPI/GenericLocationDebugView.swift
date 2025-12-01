//
//  GenericLocationDebugView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/23/25.
//

import SwiftUI

struct GenericLocationDebugView: View {
    @EnvironmentObject var genericLocation: GenericLocation

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Text("Location Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                genericLocation.locationIsStale
                                    ? Color.red : Color.green
                            )
                            .frame(width: 10, height: 10)
                        Text(
                            genericLocation.locationIsStale ? "Stale" : "Active"
                        )
                        .foregroundColor(
                            genericLocation.locationIsStale ? .red : .green
                        )
                    }
                }

                HStack {
                    Text("Last Update")
                    Spacer()
                    if let lastUpdate = genericLocation.lastUpdateTime {
                        Text(timeAgo(from: lastUpdate))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Current Position") {
                HStack {
                    Text("Latitude")
                    Spacer()
                    Text("\(genericLocation.latitude, specifier: "%.6f")°")
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                HStack {
                    Text("Longitude")
                    Spacer()
                    Text("\(genericLocation.longitude, specifier: "%.6f")°")
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                HStack {
                    Text("Altitude")
                    Spacer()
                    Text("\(genericLocation.altitude, specifier: "%.0f") ft")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            }

            Section("Motion Data") {
                HStack {
                    Text("Ground Speed")
                    Spacer()
                    if let groundSpeed = genericLocation.groundSpeed {
                        Text("\(groundSpeed, specifier: "%.1f") kts")
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Track")
                    Spacer()
                    if let track = genericLocation.track {
                        Text("\(track, specifier: "%.1f")°")
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Destination Data") {
                HStack {
                    Text("Distance")
                    Spacer()
                    Text(
                        "\(genericLocation.distanceToDestination, specifier: "%.2f") nm"
                    )
                    .foregroundColor(.secondary)
                    .monospaced()
                }

                HStack {
                    Text("Bearing to Destination")
                    Spacer()
                    if let bearing = genericLocation.bearingToDestination {
                        Text("\(bearing, specifier: "%.1f")°")
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Relative Bearing")
                    Spacer()
                    if let relativeBearing = genericLocation
                        .relativeBearingToDestination
                    {
                        let color: Color =
                            abs(relativeBearing) < 5
                            ? .green
                            : (abs(relativeBearing) < 30 ? .orange : .red)
                        Text(
                            "\(relativeBearing > 0 ? "+" : "")\(relativeBearing, specifier: "%.1f")°"
                        )
                        .foregroundColor(color)
                        .monospaced()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Angle to Destination")
                    Spacer()
                    Text(
                        "\(genericLocation.angleToDestination, specifier: "%.2f")°"
                    )
                    .foregroundColor(.secondary)
                    .monospaced()
                }

                HStack {
                    Text("Angle Deviation")
                    Spacer()
                    let deviation = genericLocation.angleDeviation
                    let color: Color =
                        abs(deviation) < 0.15
                        ? .green : (abs(deviation) < 0.45 ? .orange : .red)
                    Text(
                        "\(deviation > 0 ? "+" : "")\(deviation, specifier: "%.2f")°"
                    )
                    .foregroundColor(color)
                    .monospaced()
                }
            }

            Section("Glide Slope / PAPI") {
                HStack {
                    Text("GS Offset")
                    Spacer()
                    let offset = genericLocation.gsOffset
                    let color: Color =
                        abs(offset) < 0.15
                        ? .green : (abs(offset) < 0.35 ? .orange : .red)
                    Text("\(offset > 0 ? "+" : "")\(offset, specifier: "%.3f")")
                        .foregroundColor(color)
                        .monospaced()
                }

                HStack {
                    Text("PAPI Position")
                    Spacer()
                    Text("\(genericLocation.papiPosition, specifier: "%.3f")")
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                HStack {
                    Text("PAPI Colors")
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<4) { index in
                            let value = genericLocation.papiColors[index]
                            Circle()
                                .fill(
                                    value > 0.5
                                        ? Color.white : Color.red
                                )
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .navigationTitle("GenericLocation Debug")
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 2 {
            return "Just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            return "\(hours)h ago"
        }
    }
}

#Preview {
    NavigationStack {
        GenericLocationDebugView()
            .environmentObject(GenericLocation())
    }
}
