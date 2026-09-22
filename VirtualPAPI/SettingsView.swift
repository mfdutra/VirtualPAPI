import Network
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var genericLocation: GenericLocation
    @Environment(\.openURL) private var openURL
    @State var ipAddress: String = ""
    @State private var databaseModifiedDate: Date?
    @State private var tableCounts: (airports: Int, runways: Int)?
    @State private var databaseOpenError: String?
    @State private var isUpdating = false
    @State private var updateMessage: String?
    @State private var showError = false

    var body: some View {
        List {
            Section("Location source") {
                Picker("Source", selection: $settings.locationSource) {
                    ForEach(LocationSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
            }

            Section("Visualization") {
                Picker("Type", selection: $settings.visualization) {
                    ForEach(VisualizationType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                Picker("Responsiveness", selection: $settings.emaAlpha) {
                    Text("Smooth").tag(0.2)
                    Text("Medium").tag(0.5)
                    Text("Fast").tag(0.8)
                    Text("Instantaneous").tag(1.0)
                }

                Picker("Header size", selection: $settings.headerSize) {
                    ForEach(HeaderSize.allCases) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
            }

            Section("Network") {
                HStack {
                    Text("Local IP")
                    Spacer()
                    Text(ipAddress.isEmpty ? "Unknown" : ipAddress)
                        .foregroundColor(.secondary)
                }
            }

            Section("Aviation Database") {
                HStack {
                    Text("Last Modified")
                    Spacer()
                    if let modifiedDate = databaseModifiedDate {
                        Text(formatDate(modifiedDate))
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("Unknown")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Airports")
                    Spacer()
                    if databaseOpenError != nil {
                        Text("Unavailable")
                            .foregroundColor(.red)
                    } else if let counts = tableCounts {
                        Text("\(counts.airports)")
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Runways")
                    Spacer()
                    if let counts = tableCounts {
                        Text("\(counts.runways)")
                            .foregroundColor(.secondary)
                            .monospaced()
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }

                if let error = databaseOpenError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(action: {
                    updateDatabase()
                }) {
                    HStack {
                        if isUpdating {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(
                            isUpdating
                                ? "Checking for updates..."
                                : "Check for Updates"
                        )
                    }
                }
                .disabled(isUpdating)

                if let message = updateMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(showError ? .red : .green)
                }
            }

            Section("Debug") {
                Toggle("Show Debug Info", isOn: $settings.showDebugInfo)

                NavigationLink("GDL90 Debug", destination: GDL90DebugView())
                NavigationLink(
                    "Internal GPS Debug",
                    destination: InternalLocationDebugView()
                )
                NavigationLink(
                    "Generic location debug",
                    destination: GenericLocationDebugView()
                )

                NavigationLink(
                    "Destination Map",
                    destination: DestinationMapView()
                )

                Button("Destination in Google Maps") {
                    if let url = googleMapsURL {
                        openURL(url)
                    }
                }
                .disabled(googleMapsURL == nil)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            getLocalIPAddress()
            loadDatabaseModifiedDate()
            loadTableCounts()
        }
    }

    /// Google Maps universal link pinned at the selected destination.
    /// iOS opens the Google Maps app when installed, otherwise the browser.
    private var googleMapsURL: URL? {
        guard
            let lat = genericLocation.airportSelection?.targetLatitude,
            let lon = genericLocation.airportSelection?.targetLongitude
        else { return nil }

        var components = URLComponents(
            string: "https://www.google.com/maps/search/"
        )
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(lat),\(lon)"),
        ]
        return components?.url
    }

    private func loadDatabaseModifiedDate() {
        let dbPath = getDatabasePath()

        if let attributes = try? FileManager.default.attributesOfItem(
            atPath: dbPath
        ),
            let modDate = attributes[.modificationDate] as? Date
        {
            databaseModifiedDate = modDate
        }
    }

    private func loadTableCounts() {
        tableCounts = DatabaseManager.shared.getTableRowCounts()
        databaseOpenError =
            DatabaseManager.shared.openFailure?.localizedDescription
    }

    private func getDatabasePath() -> String {
        let paths = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("aviation.db").path
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func updateDatabase() {
        isUpdating = true
        updateMessage = nil
        showError = false

        Task {
            do {
                let wasUpdated = try await DatabaseManager.shared
                    .downloadRemoteDatabase()

                await MainActor.run {
                    if wasUpdated {
                        updateMessage = "Database updated successfully"
                        showError = false
                        loadDatabaseModifiedDate()
                        loadTableCounts()
                    } else {
                        updateMessage = "Database is already up-to-date"
                        showError = false
                    }
                    isUpdating = false
                }
            } catch {
                await MainActor.run {
                    updateMessage =
                        "Update failed: \(error.localizedDescription)"
                    print("Update failed: \(error.localizedDescription)")
                    showError = true
                    isUpdating = false
                }
            }
        }
    }

    private func getLocalIPAddress() {
        ipAddress = Self.localIPAddress() ?? "Unknown"
    }

    /// IPv4 address of the Wi-Fi interface (en0/en1), or nil when there is
    /// none. `ifa_addr` and `ifa_name` are imported as implicitly unwrapped
    /// optionals but can be NULL (e.g. an interface with no assigned
    /// address), so both are checked before being dereferenced.
    nonisolated static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        guard let firstAddr = ifaddr else {
            return nil
        }

        return sequence(first: firstAddr, next: { $0.pointee.ifa_next })
            .lazy
            .compactMap { ptr -> String? in
                let interface = ptr.pointee

                guard let addr = interface.ifa_addr,
                    addr.pointee.sa_family == UInt8(AF_INET),
                    let namePtr = interface.ifa_name
                else { return nil }

                let name = String(cString: namePtr)
                guard name == "en0" || name == "en1" else { return nil }

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard
                    getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    ) == 0
                else { return nil }

                return String(cString: hostname)
            }
            .first
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .environmentObject(GenericLocation())
}
