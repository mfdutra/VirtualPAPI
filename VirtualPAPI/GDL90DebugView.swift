//
//  GDL90DebugView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/20/25.
//

import SwiftUI

struct GDL90DebugView: View {
    @EnvironmentObject var gdl90Reader: GDL90Reader

    var body: some View {
        List {
            Section("Connection") {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                gdl90Reader.isConnected
                                    ? Color.green : Color.red
                            )
                            .frame(width: 10, height: 10)
                        Text(
                            gdl90Reader.isConnected
                                ? "Connected" : "Disconnected"
                        )
                        .foregroundColor(
                            gdl90Reader.isConnected ? .green : .red
                        )
                    }
                }

                HStack {
                    Text("Last Update")
                    Spacer()
                    Text(timeAgo(from: gdl90Reader.lastUpdateTime))
                        .foregroundColor(.secondary)
                }
            }

            Section("Position (Message 10)") {
                HStack {
                    Text("Latitude")
                    Spacer()
                    Text("\(gdl90Reader.latitude, specifier: "%.6f")°")
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                HStack {
                    Text("Longitude")
                    Spacer()
                    Text("\(gdl90Reader.longitude, specifier: "%.6f")°")
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                HStack {
                    Text("Pressure Altitude")
                    Spacer()
                    Text("\(gdl90Reader.altitude, specifier: "%.0f") ft")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                HStack {
                    Text("Speed")
                    Spacer()
                    Text("\(gdl90Reader.groundSpeed, specifier: "%.0f") kt")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                HStack {
                    Text("Heading")
                    Spacer()
                    Text("\(gdl90Reader.track, specifier: "%.0f")°")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
            }

            Section("Altitude (Message 11)") {
                HStack {
                    Text("Geometric Altitude")
                    Spacer()
                    Text(
                        "\(gdl90Reader.geometricAltitude, specifier: "%.0f") ft"
                    )
                    .foregroundColor(.secondary)
                    .monospaced()
                }

                HStack {
                    Text("Altitude Difference")
                    Spacer()
                    let diff =
                        gdl90Reader.geometricAltitude - gdl90Reader.altitude
                    Text("\(diff > 0 ? "+" : "")\(diff, specifier: "%.0f") ft")
                        .foregroundColor(
                            diff > 0
                                ? .green : (diff < 0 ? .orange : .secondary)
                        )
                        .monospaced()
                }
            }

            Section("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GDL90 Protocol")
                        .font(.headline)
                    Text("Listening on UDP port 4000")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    Text("Supported Messages:")
                        .font(.subheadline)
                        .bold()

                    HStack {
                        Image(systemName: "10.circle.fill")
                            .foregroundColor(.blue)
                        Text("Ownship Report")
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "11.circle.fill")
                            .foregroundColor(.blue)
                        Text("Ownship Geometric Altitude")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("GDL90 Debug")
        .onAppear {
            gdl90Reader.startListening()
        }
        .onDisappear {
            gdl90Reader.stopListening()
        }
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
        GDL90DebugView()
            .environmentObject(GDL90Reader())
    }
}
