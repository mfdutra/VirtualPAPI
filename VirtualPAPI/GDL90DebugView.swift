//
//  GDL90DebugView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/20/25.
//

import SwiftUI

struct GDL90DebugView: View {
    @EnvironmentObject var gdl90Reader: GDL90Reader
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        List {
            Section("Connection") {
                if settings.locationSource != .gdl90 {
                    Text(
                        "GDL90 is not the selected location source. Select GDL90 in Settings to start listening."
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                }

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

                HStack {
                    Text("Heartbeat")
                    Spacer()
                    Text(gdl90Reader.heartbeatStatus.description)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(heartbeatColor)
                }
            }

            Section("Device Heartbeat (Message 0)") {
                HStack {
                    Text("GPS Position")
                    Spacer()
                    Text(
                        gdl90Reader.deviceGPSValid.map { $0 ? "Valid" : "Not valid" }
                            ?? "No heartbeat"
                    )
                    .foregroundColor(
                        gdl90Reader.deviceGPSValid.map { $0 ? .green : .red } ?? .secondary
                    )
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
                    Text(
                        gdl90Reader.altitude.map { String(format: "%.0f ft", $0) }
                            ?? "Invalid"
                    )
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
                    Text("NIC")
                    Spacer()
                    Text(
                        gdl90Reader.nic >= GDL90Reader.minimumNIC
                            ? "\(gdl90Reader.nic)" : "\(gdl90Reader.nic) (no valid position)"
                    )
                    .foregroundColor(
                        gdl90Reader.nic >= GDL90Reader.minimumNIC ? .secondary : .red
                    )
                    .monospaced()
                }
                HStack {
                    Text(gdl90Reader.trackType == .trueTrack ? "Track" : "Track/Heading")
                    Spacer()
                    Text("\(gdl90Reader.track, specifier: "%.0f")°")
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                HStack {
                    Text("Track Type")
                    Spacer()
                    Text(gdl90Reader.trackType.description)
                        .foregroundColor(
                            gdl90Reader.trackType == .trueTrack ? .secondary : .orange
                        )
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
                    if let altitude = gdl90Reader.altitude {
                        let diff = gdl90Reader.geometricAltitude - altitude
                        Text("\(diff > 0 ? "+" : "")\(diff, specifier: "%.0f") ft")
                            .foregroundColor(
                                diff > 0
                                    ? .green : (diff < 0 ? .orange : .secondary)
                            )
                            .monospaced()
                    } else {
                        Text("---")
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                }
            }

            Section("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GDL90 Protocol")
                        .font(.headline)
                    Text("Listening on UDP ports 4000 and 43211")
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
    }

    private var heartbeatColor: Color {
        switch gdl90Reader.heartbeatStatus {
        case .sent: return .green
        case .failed: return .red
        case .waiting: return .orange
        case .idle: return .secondary
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
            .environmentObject(AppSettings())
    }
}
