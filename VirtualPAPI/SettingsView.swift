import SwiftUI
import Network

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State var ipAddress: String = ""
    
    var body: some View {
        List {
            Section("Location source") {
                Picker("Source", selection: $settings.locationSource) {
                    ForEach(LocationSource.allCases) { source in
                        Text(source.rawValue).tag(source)
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
            
            Section("Debug") {
                Toggle("Show Debug Info", isOn: $settings.showDebugInfo)

                NavigationLink("GDL90 Debug", destination: GDL90DebugView())
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            getLocalIPAddress()
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
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST)
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
