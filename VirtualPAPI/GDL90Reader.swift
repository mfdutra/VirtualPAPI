//
//  GDL90Reader.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/20/25.
//

import Combine
import Foundation
import Network

@MainActor
class GDL90Reader: ObservableObject {
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var altitude: Double = 0.0  // Pressure altitude from message 10
    @Published var geometricAltitude: Double = 0.0  // Geometric altitude from message 11
    @Published var groundSpeed: Double = 0.0
    @Published var track: Double = 0.0
    @Published var isConnected: Bool = false
    @Published var lastUpdateTime: Date = Date()

    private var udpListener: NWListener?
    private var udpConnection: NWConnection?
    private var broadcastTimer: Timer?
    private let queue = DispatchQueue(label: "gdl90-udp-queue")

    var genericLocation: GenericLocation?
    var appSettings: AppSettings?

    deinit {
        udpListener?.cancel()
        udpConnection?.cancel()
        broadcastTimer?.invalidate()
        udpListener = nil
        udpConnection = nil
        broadcastTimer = nil
    }

    func startListening() {
        let port = NWEndpoint.Port(4000)
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        udpListener = try? NWListener(using: parameters, on: port)

        udpListener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { @MainActor in
                self.udpConnection = connection
                self.setupConnection(connection)
            }
        }

        udpListener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isConnected = true
                case .failed(let error):
                    print("GDL90 listener failed: \(error)")
                    self.isConnected = false
                case .cancelled:
                    self.isConnected = false
                default:
                    break
                }
            }
        }

        udpListener?.start(queue: queue)
        startBroadcastHeartbeat()
    }

    private func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.receiveData(from: connection)
                case .failed(let error):
                    print("GDL90 connection failed: \(error)")
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
    }

    func stopListening() {
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        udpListener?.cancel()
        udpConnection?.cancel()
        udpListener = nil
        udpConnection = nil
    }

    private func startBroadcastHeartbeat() {
        // Send initial broadcast immediately
        Task { @MainActor in
            await self.sendBroadcast()
        }

        // Schedule broadcasts every 5 seconds
        broadcastTimer = Timer.scheduledTimer(
            withTimeInterval: 5.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.sendBroadcast()
            }
        }
    }

    private func sendBroadcast() async {
        let jsonString =
            "{\"App\": \"VirtualPAPI\", \"GDL90\": {\"port\": 4000}}"
        guard let data = jsonString.data(using: .utf8) else { return }

        // Create a UDP connection for broadcasting
        let broadcastEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("255.255.255.255"),
            port: NWEndpoint.Port(integerLiteral: 63093)
        )

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .wifi

        let connection = NWConnection(to: broadcastEndpoint, using: parameters)

        connection.stateUpdateHandler = { (state: NWConnection.State) in
            if case .ready = state {
                connection.send(content: data, completion: .idempotent)
            } else if case .failed(let error) = state {
                print("Broadcast connection failed: \(error)")
            }
        }

        connection.start(queue: queue)

        // Wait a bit for the send to complete, then cancel
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        connection.cancel()
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, context, isComplete, error in
            guard let self else { return }

            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self.processGDL90Data(data)
                }
            }

            if error == nil {
                Task { @MainActor in
                    self.receiveData(from: connection)
                }
            }
        }
    }

    private func updateGenericLocation(
        _ latitude: Double,
        _ longitude: Double,
        _ altitude: Double,
        _ speed: Double?,
        _ track: Double?
    ) {
        // Only update GenericLocation if GDL90 is the selected source
        if appSettings?.locationSource == .gdl90 {
            self.genericLocation?.updateLocation(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speed: speed,
                track: track
            )
        }
    }

    func processGDL90Data(_ data: Data) {
        let messages = parseGDL90Messages(data)

        for message in messages {
            guard !message.isEmpty else { continue }

            let messageID = message[0]

            switch messageID {
            case 10:  // Ownship Report
                parseOwnshipReport(message)
            case 11:  // Ownship Geometric Altitude
                parseOwnshipGeometricAltitude(message)
            default:
                break
            }
        }
    }

    // Parse GDL90 framing: extract messages between 0x7E flags and unstuff bytes
    private func parseGDL90Messages(_ data: Data) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var currentMessage: [UInt8] = []
        var inMessage = false
        var escapeNext = false

        for byte in data {
            if byte == 0x7E {  // Flag byte
                if inMessage && !currentMessage.isEmpty {
                    // End of message - validate CRC and extract payload
                    if currentMessage.count >= 3 {
                        let payload = Array(
                            currentMessage[0..<(currentMessage.count - 2)]
                        )
                        // GDL90 CRC is stored as little-endian (low byte first, high byte second)
                        let crc =
                            UInt16(currentMessage[currentMessage.count - 2])
                            | (UInt16(currentMessage[currentMessage.count - 1])
                                << 8)

                        if validateCRC(payload, crc: crc) {
                            messages.append(payload)
                        }
                    }
                    currentMessage.removeAll()
                }
                inMessage = true
                escapeNext = false
            } else if inMessage {
                if escapeNext {
                    currentMessage.append(byte ^ 0x20)
                    escapeNext = false
                } else if byte == 0x7D {  // Escape byte
                    escapeNext = true
                } else {
                    currentMessage.append(byte)
                }
            }
        }

        return messages
    }

    // Simplified CRC validation for GDL90
    private func validateCRC(_ payload: [UInt8], crc: UInt16) -> Bool {
        let calculatedCRC = calculateCRC(payload)
        return calculatedCRC == crc
    }

    // GDL90 CRC-16-CCITT lookup table (polynomial 0x1021)
    private let crc16Table: [UInt16] = [
        0x0000, 0x1021, 0x2042, 0x3063, 0x4084, 0x50a5, 0x60c6, 0x70e7,
        0x8108, 0x9129, 0xa14a, 0xb16b, 0xc18c, 0xd1ad, 0xe1ce, 0xf1ef,
        0x1231, 0x0210, 0x3273, 0x2252, 0x52b5, 0x4294, 0x72f7, 0x62d6,
        0x9339, 0x8318, 0xb37b, 0xa35a, 0xd3bd, 0xc39c, 0xf3ff, 0xe3de,
        0x2462, 0x3443, 0x0420, 0x1401, 0x64e6, 0x74c7, 0x44a4, 0x5485,
        0xa56a, 0xb54b, 0x8528, 0x9509, 0xe5ee, 0xf5cf, 0xc5ac, 0xd58d,
        0x3653, 0x2672, 0x1611, 0x0630, 0x76d7, 0x66f6, 0x5695, 0x46b4,
        0xb75b, 0xa77a, 0x9719, 0x8738, 0xf7df, 0xe7fe, 0xd79d, 0xc7bc,
        0x48c4, 0x58e5, 0x6886, 0x78a7, 0x0840, 0x1861, 0x2802, 0x3823,
        0xc9cc, 0xd9ed, 0xe98e, 0xf9af, 0x8948, 0x9969, 0xa90a, 0xb92b,
        0x5af5, 0x4ad4, 0x7ab7, 0x6a96, 0x1a71, 0x0a50, 0x3a33, 0x2a12,
        0xdbfd, 0xcbdc, 0xfbbf, 0xeb9e, 0x9b79, 0x8b58, 0xbb3b, 0xab1a,
        0x6ca6, 0x7c87, 0x4ce4, 0x5cc5, 0x2c22, 0x3c03, 0x0c60, 0x1c41,
        0xedae, 0xfd8f, 0xcdec, 0xddcd, 0xad2a, 0xbd0b, 0x8d68, 0x9d49,
        0x7e97, 0x6eb6, 0x5ed5, 0x4ef4, 0x3e13, 0x2e32, 0x1e51, 0x0e70,
        0xff9f, 0xefbe, 0xdfdd, 0xcffc, 0xbf1b, 0xaf3a, 0x9f59, 0x8f78,
        0x9188, 0x81a9, 0xb1ca, 0xa1eb, 0xd10c, 0xc12d, 0xf14e, 0xe16f,
        0x1080, 0x00a1, 0x30c2, 0x20e3, 0x5004, 0x4025, 0x7046, 0x6067,
        0x83b9, 0x9398, 0xa3fb, 0xb3da, 0xc33d, 0xd31c, 0xe37f, 0xf35e,
        0x02b1, 0x1290, 0x22f3, 0x32d2, 0x4235, 0x5214, 0x6277, 0x7256,
        0xb5ea, 0xa5cb, 0x95a8, 0x8589, 0xf56e, 0xe54f, 0xd52c, 0xc50d,
        0x34e2, 0x24c3, 0x14a0, 0x0481, 0x7466, 0x6447, 0x5424, 0x4405,
        0xa7db, 0xb7fa, 0x8799, 0x97b8, 0xe75f, 0xf77e, 0xc71d, 0xd73c,
        0x26d3, 0x36f2, 0x0691, 0x16b0, 0x6657, 0x7676, 0x4615, 0x5634,
        0xd94c, 0xc96d, 0xf90e, 0xe92f, 0x99c8, 0x89e9, 0xb98a, 0xa9ab,
        0x5844, 0x4865, 0x7806, 0x6827, 0x18c0, 0x08e1, 0x3882, 0x28a3,
        0xcb7d, 0xdb5c, 0xeb3f, 0xfb1e, 0x8bf9, 0x9bd8, 0xabbb, 0xbb9a,
        0x4a75, 0x5a54, 0x6a37, 0x7a16, 0x0af1, 0x1ad0, 0x2ab3, 0x3a92,
        0xfd2e, 0xed0f, 0xdd6c, 0xcd4d, 0xbdaa, 0xad8b, 0x9de8, 0x8dc9,
        0x7c26, 0x6c07, 0x5c64, 0x4c45, 0x3ca2, 0x2c83, 0x1ce0, 0x0cc1,
        0xef1f, 0xff3e, 0xcf5d, 0xdf7c, 0xaf9b, 0xbfba, 0x8fd9, 0x9ff8,
        0x6e17, 0x7e36, 0x4e55, 0x5e74, 0x2e93, 0x3eb2, 0x0ed1, 0x1ef0,
    ]

    // GDL90 uses table-driven CRC-16-CCITT (polynomial 0x1021, init 0x0000)
    // This matches the Python implementation in gdl90/fcs.py exactly:
    // crc = CRC16Table[(crc >> 8)] ^ m ^ c where m = (crc << 8) & 0xffff
    private func calculateCRC(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0x0000

        for byte in data {
            let m = (crc << 8) & 0xFFFF
            crc = crc16Table[Int(crc >> 8)] ^ m ^ UInt16(byte)
        }

        return crc
    }

    // Parse Message ID 10: Ownship Report
    private func parseOwnshipReport(_ message: [UInt8]) {
        guard message.count >= 28 else { return }

        // Bytes 5-7: Latitude (24-bit signed, BIG-ENDIAN, LSB = 180/2^23 degrees)
        let latRaw =
            (Int32(message[5]) << 16) | (Int32(message[6]) << 8)
            | Int32(message[7])
        let latSigned = (latRaw & 0x800000) != 0 ? latRaw - 0x1000000 : latRaw
        let latitude = Double(latSigned) * (180.0 / pow(2.0, 23.0))

        // Bytes 8-10: Longitude (24-bit signed, BIG-ENDIAN, LSB = 180/2^23 degrees)
        let lonRaw =
            (Int32(message[8]) << 16) | (Int32(message[9]) << 8)
            | Int32(message[10])
        let lonSigned = (lonRaw & 0x800000) != 0 ? lonRaw - 0x1000000 : lonRaw
        let longitude = Double(lonSigned) * (180.0 / pow(2.0, 23.0))

        // Bytes 11-12: Altitude (12-bit value, resolution 25 feet, offset -1000 feet)
        // Python: altMetric = _thunkByte(msgBytes[11], 0xff, 4) + _thunkByte(msgBytes[12], 0xf0, -4)
        // Which is: (msgBytes[11] << 4) | ((msgBytes[12] & 0xf0) >> 4)
        let altMetric =
            (UInt16(message[11]) << 4) | ((UInt16(message[12]) & 0xF0) >> 4)
        let altitude = Double(altMetric) * 25.0 - 1000.0

        // Bytes 14-15: Horizontal velocity (12-bit value, resolution 1 knot)
        // Byte 14 = upper 8 bits, upper nibble of byte 15 = lower 4 bits
        let velocityRaw =
            (UInt16(message[14]) << 4) | ((UInt16(message[15]) & 0xF0) >> 4)
        let speed: Double? = velocityRaw == 0xFFF ? nil : Double(velocityRaw)

        // Byte 17: Track/heading (8-bit value, LSB = 360/256 = 1.40625 degrees)
        let trackRaw = message[17]
        let track: Double = Double(trackRaw) * (360.0 / 256.0)

        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.groundSpeed = speed ?? 0
        self.track = track
        self.lastUpdateTime = Date()

        updateGenericLocation(latitude, longitude, altitude, speed, track)
    }

    // Parse Message ID 11: Ownship Geometric Altitude
    private func parseOwnshipGeometricAltitude(_ message: [UInt8]) {
        guard message.count >= 5 else { return }

        // Bytes 1-2: Geometric altitude (16-bit signed big-endian, resolution 5 feet)
        // Python: _signed16(msgBytes[1:]) * 5
        // _signed16 reads big-endian: (data[0] << 8) + data[1]
        let altUnsigned = (UInt16(message[1]) << 8) | UInt16(message[2])
        let altSigned =
            altUnsigned > 0x7FFF
            ? Int16(bitPattern: altUnsigned) : Int16(altUnsigned)
        let geometricAlt = Double(altSigned) * 5.0

        self.geometricAltitude = geometricAlt

        // Optionally update the main altitude with geometric altitude
        // For now, just store it separately
    }
}
