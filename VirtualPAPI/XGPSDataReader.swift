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
        var buffer = [UInt8](repeating: 0, count: 65536)

        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { ptr -> Int in
                recvfrom(fd, ptr.baseAddress, ptr.count, 0, nil, nil)
            }

            guard bytesRead > 0 else { break }  // socket closed or error

            let data = Data(bytes: buffer, count: bytesRead)
            Task { @MainActor [weak self] in
                self?.processXGPSData(data)
            }
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

    func processXGPSData(_ data: Data) {
        guard data.count >= 41 else { return }

        let header = String(data: data.prefix(4), encoding: .ascii)
        guard header == "XGPS" else { return }

        let dataStr = String(data: data, encoding: .ascii)
        let components = dataStr?.components(separatedBy: ",")

        let longitude = Double(components?[1] ?? "") ?? 0
        let latitude = Double(components?[2] ?? "") ?? 0
        let altitude = (Double(components?[3] ?? "") ?? 0) * 3.2808399  // meter to feet
        let track = Double(components?[4] ?? "") ?? 0
        let speed = (Double(components?[5] ?? "") ?? 0) * 1.9438445  // m/s to knots

        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.groundSpeed = speed
        self.track = track
        self.lastUpdateTime = Date()

        updateGenericLocation(latitude, longitude, altitude, speed, track)
    }
}
