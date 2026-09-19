import Combine
import Darwin
import Foundation

@MainActor
class XGPSDataReader: ObservableObject {
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0
    @Published var groundSpeed: Double = 0.0
    @Published var track: Double = 0.0
    @Published var isConnected: Bool = false
    @Published var lastUpdateTime: Date = Date()

    private var socketFD: Int32 = -1
    private var receiveThread: Thread?

    var genericLocation: GenericLocation?
    var appSettings: AppSettings?

    deinit {
        if socketFD >= 0 {
            close(socketFD)
        }
    }

    func startListening() {
        guard socketFD < 0 else { return }  // already listening
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            print("XGPS: failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        // Never call connect() on this socket: a "connected" socket takes
        // priority over other apps' plain listening sockets for matching
        // packets, which would steal broadcast traffic from them.
        var reuseAddr: Int32 = 1
        setsockopt(
            fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr,
            socklen_t(MemoryLayout<Int32>.size))
        var reusePort: Int32 = 1
        setsockopt(
            fd, SOL_SOCKET, SO_REUSEPORT, &reusePort,
            socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(49002).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("XGPS: bind failed: \(String(cString: strerror(errno)))")
            close(fd)
            return
        }

        socketFD = fd
        isConnected = true

        let thread = Thread { [weak self] in
            self?.receiveLoop(fd: fd)
        }
        thread.name = "xgps-udp-receive"
        thread.start()
        receiveThread = thread
    }

    private nonisolated func receiveLoop(fd: Int32) {
        runUDPReceiveLoop(fd: fd, label: "XGPS") { data in
            Task { @MainActor [weak self] in
                self?.processXGPSData(data)
            }
        }

        // The loop only returns on a fatal socket error. If this thread is
        // still the active receiver, stopListening() didn't cause it, so
        // surface the failure instead of silently going quiet.
        let thread = Thread.current
        Task { @MainActor [weak self] in
            guard let self, self.receiveThread === thread else { return }
            print("XGPS: receive loop exited unexpectedly")
            self.stopListening()
        }
    }

    func stopListening() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        receiveThread = nil
        isConnected = false
    }

    fileprivate func updateGenericLocation(
        _ latitude: Double,
        _ longitude: Double,
        _ altitude: Double,
        _ speed: Double,
        _ track: Double
    ) {
        if appSettings!.locationSource == .xPlane {
            self.genericLocation?.updateLocation(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speed: speed,
                track: track
            )
        }
    }

    struct XGPSFix: Equatable {
        let latitude: Double
        let longitude: Double
        let altitude: Double  // feet
        let groundSpeed: Double  // knots
        let track: Double  // degrees
    }

    /// Parses an XGPS packet ("XGPS<name>,lon,lat,alt_m,track,speed_m/s").
    /// Returns nil if the packet is too short, has the wrong header, has
    /// fewer than 6 comma-separated fields, any used field isn't numeric or
    /// is non-finite (Double(String) accepts "nan"/"inf"), latitude/longitude
    /// are outside ±90/±180, or altitude is outside
    /// GenericLocation.plausibleAltitudeRange. Track is normalized to 0..<360.
    nonisolated static func parseXGPS(_ data: Data) -> XGPSFix? {
        guard data.count >= 41,
            String(data: data.prefix(4), encoding: .ascii) == "XGPS",
            let components = String(data: data, encoding: .ascii)?
                .components(separatedBy: ","),
            components.count >= 6
        else { return nil }

        let values = components[1...5].compactMap {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)))
        }
        guard values.count == 5, values.allSatisfy(\.isFinite) else { return nil }

        let altitude = values[2] * 3.2808399  // meter to feet
        guard
            GenericLocation.isValidCoordinate(latitude: values[1], longitude: values[0]),
            GenericLocation.plausibleAltitudeRange.contains(altitude)
        else { return nil }

        let track = values[3].truncatingRemainder(dividingBy: 360)

        return XGPSFix(
            latitude: values[1],
            longitude: values[0],
            altitude: altitude,
            groundSpeed: values[4] * 1.9438445,  // m/s to knots
            track: track < 0 ? track + 360 : track
        )
    }

    func processXGPSData(_ data: Data) {
        guard let fix = Self.parseXGPS(data) else { return }

        self.latitude = fix.latitude
        self.longitude = fix.longitude
        self.altitude = fix.altitude
        self.groundSpeed = fix.groundSpeed
        self.track = fix.track
        self.lastUpdateTime = Date()

        updateGenericLocation(fix.latitude, fix.longitude, fix.altitude, fix.groundSpeed, fix.track)
    }
}
