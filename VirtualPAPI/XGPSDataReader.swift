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

    private static let listenPort: UInt16 = 49002

    private var receiver: UDPReceiver?

    var genericLocation: GenericLocation?
    var appSettings: AppSettings?

    deinit {
        receiver?.stop()
    }

    func startListening() {
        guard receiver == nil else { return }  // already listening
        guard let receiver = UDPReceiver.open(port: Self.listenPort, label: "XGPS") else {
            return
        }

        self.receiver = receiver
        isConnected = true

        receiver.start(
            onDatagram: { [weak self] data in
                Task { @MainActor [weak self] in
                    self?.processXGPSData(data)
                }
            },
            onUnexpectedExit: { [weak self] in
                // Reported only when the loop ended on a fatal socket error,
                // never on a deliberate stop, so surface the failure instead
                // of silently going quiet.
                Task { @MainActor [weak self] in
                    guard let self, self.receiver === receiver else { return }
                    print("XGPS: receive loop exited unexpectedly")
                    self.stopListening()
                }
            }
        )
    }

    func stopListening() {
        // stop() returns only once the receive thread has exited and the
        // socket is closed, so a restart can rebind immediately.
        receiver?.stop()
        receiver = nil
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
