import Network
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State var ipAddress: String = ""
    @State private var databaseModifiedDate: Date?
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
                    "Generic location debug",
                    destination: GenericLocationDebugView()
                )
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            getLocalIPAddress()
            loadDatabaseModifiedDate()
        }
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
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else {
            return
        }

        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                    break
                }
            }
        }

        DispatchQueue.main.async {
            self.ipAddress = address ?? "Unknown"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
