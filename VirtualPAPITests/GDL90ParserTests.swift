//
//  GDL90ParserTests.swift
//  VirtualPAPITests
//
//  Framing, CRC and field-decoding tests for GDL90Reader.
//

import Foundation
import Testing

@testable import VirtualPAPI

// MARK: - Frame building helpers

/// Builds GDL90 frames the way a device would: payload -> CRC -> byte
/// stuffing -> 0x7E flags.
///
/// The CRC table here is derived from the polynomial (0x1021) with the bitwise
/// algorithm published in the GDL90 spec, deliberately *not* copied from
/// `GDL90Reader`'s hard-coded table, so these tests can't agree with a wrong
/// table. `testSpecHeartbeatCRC` anchors it to the worked example in the spec.
enum GDL90TestFrame {

    static let crcTable: [UInt16] = (0..<256).map { i in
        (0..<8).reduce(UInt16(i) << 8) { crc, _ in
            (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
        }
    }

    /// GDL90 spec: crc = Table[crc >> 8] ^ (crc << 8) ^ byte, init 0x0000.
    static func crc(_ payload: [UInt8]) -> UInt16 {
        payload.reduce(UInt16(0)) { crc, byte in
            crcTable[Int(crc >> 8)] ^ (crc << 8) ^ UInt16(byte)
        }
    }

    static func stuff(_ bytes: [UInt8]) -> [UInt8] {
        bytes.flatMap { byte in
            byte == 0x7E || byte == 0x7D ? [0x7D, byte ^ 0x20] : [byte]
        }
    }

    /// Complete frame: 0x7E, stuffed(payload + little-endian CRC), 0x7E.
    static func frame(_ payload: [UInt8]) -> Data {
        let checksum = crc(payload)
        let body = payload + [UInt8(checksum & 0xFF), UInt8(checksum >> 8)]
        return Data([0x7E] + stuff(body) + [0x7E])
    }

    /// Frame without the closing flag, i.e. a datagram cut short.
    static func unterminatedFrame(_ payload: [UInt8]) -> Data {
        frame(payload).dropLast()
    }

    private static func be24(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// Message ID 10 (Ownship Report), 28 bytes, raw field values as they
    /// appear on the wire.
    static func ownship(
        latRaw: UInt32,
        lonRaw: UInt32,
        altRaw: UInt16 = 250,  // 250 * 25 - 1000 = 5250 ft
        velocityRaw: UInt16 = 120,  // 120 kt
        trackRaw: UInt8 = 0x40,  // 64 * 360/256 = 90 degrees
        trackType: UInt8 = 1,  // true track
        nic: UInt8 = 0x0B,
        address: [UInt8] = [0xAB, 0xCD, 0xEF],
        callSign: [UInt8] = Array("N123AB  ".utf8)
    ) -> [UInt8] {
        let byte11 = UInt8((altRaw >> 4) & 0xFF)
        let byte12 = UInt8((altRaw & 0x0F) << 4) | 0x08 | (trackType & 0x03)  // misc: airborne + track type
        let byte14 = UInt8((velocityRaw >> 4) & 0xFF)
        // low nibble of byte 15 is the top of the vertical velocity field
        let byte15 = UInt8((velocityRaw & 0x0F) << 4) | 0x08
        return [10, 0x00]  // message ID, status/address type
            + address  // bytes 2-4
            + be24(latRaw)  // bytes 5-7
            + be24(lonRaw)  // bytes 8-10
            + [byte11, byte12]  // bytes 11-12: altitude + misc
            + [(nic << 4) | 0x0B]  // byte 13: NIC/NACp
            + [byte14, byte15, 0x00]  // bytes 14-16: horizontal + vertical velocity
            + [trackRaw]  // byte 17
            + [0x01]  // byte 18: emitter category
            + callSign  // bytes 19-26
            + [0x00]  // byte 27: emergency code
    }

    /// Message ID 0 (Heartbeat), 7 bytes. Byte 1 bit 7 is "GPS Pos Valid";
    /// bit 0 (UAT initialized) is set as a real device would.
    static func heartbeat(gpsValid: Bool) -> [UInt8] {
        [0x00, gpsValid ? 0x81 : 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]
    }

    /// Message ID 11 (Ownship Geometric Altitude), 5 bytes.
    static func geometricAltitude(raw: Int16) -> [UInt8] {
        let unsigned = UInt16(bitPattern: raw)
        return [11, UInt8(unsigned >> 8), UInt8(unsigned & 0xFF), 0x00, 0x0A]
    }
}

// MARK: - GDL90 Parser Tests

@Suite("GDL90 Parser Tests")
@MainActor
struct GDL90ParserTests {

    /// A reader wired to a GenericLocation, with GDL90 as the active source so
    /// accepted reports propagate.
    private func makeReader() -> (reader: GDL90Reader, location: GenericLocation) {
        let reader = GDL90Reader()
        let location = GenericLocation()
        let settings = AppSettings(defaults: .isolatedForTesting())
        settings.locationSource = .gdl90
        reader.genericLocation = location
        reader.appSettings = settings
        return (reader, location)
    }

    /// Seeds the shared location with a recognizable fix, so a later "nothing
    /// was updated" assertion can't pass just because everything is still 0.
    private func seed(_ location: GenericLocation) {
        location.updateLocation(
            latitude: 10, longitude: 20, altitude: 3000, speed: 99, track: 45)
    }

    private func expectUnchanged(_ location: GenericLocation) {
        #expect(location.latitude == 10)
        #expect(location.longitude == 20)
        #expect(location.altitude == 3000)
    }

    // MARK: CRC

    @Test("Test CRC helper matches the worked example in the GDL90 spec")
    func testSpecHeartbeatCRC() {
        // Spec example, Heartbeat message: 7E 00 81 41 DB D0 08 02 B3 8B 7E
        // (CRC transmitted low byte first, so the value is 0x8BB3).
        let payload: [UInt8] = [0x00, 0x81, 0x41, 0xDB, 0xD0, 0x08, 0x02]
        #expect(GDL90TestFrame.crc(payload) == 0x8BB3)
    }

    // MARK: Ownship Report (message 10)

    @Test("Known-good ownship report decodes to hand-computed values")
    func testOwnshipReport() {
        let (reader, location) = makeReader()

        // latRaw 0x1B0000 = 1_769_472; 1_769_472 * 180 / 2^23 = 37.96875
        // lonRaw 0xA80000 -> signed -5_767_168; * 180 / 2^23 = -123.75
        let payload = GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000)
        reader.processGDL90Data(GDL90TestFrame.frame(payload))

        #expect(reader.latitude == 37.96875)
        #expect(reader.longitude == -123.75)
        #expect(reader.altitude == 5250)  // 250 * 25 - 1000
        #expect(reader.groundSpeed == 120)
        #expect(reader.track == 90.0)  // 0x40 * 360/256
        #expect(reader.usingGeometricAltitude == false)

        #expect(location.latitude == 37.96875)
        #expect(location.longitude == -123.75)
        #expect(location.altitude == 5250)
        #expect(location.groundSpeed == 120)
        #expect(location.track == 90.0)
    }

    @Test("Track resolution is 360/256 degrees per count")
    func testTrackResolution() {
        let (reader, _) = makeReader()
        let cases: [(UInt8, Double)] = [
            (0x00, 0.0), (0x01, 1.40625), (0x20, 45.0), (0x80, 180.0), (0xFF, 358.59375),
        ]
        cases.forEach { raw, expected in
            reader.processGDL90Data(
                GDL90TestFrame.frame(
                    GDL90TestFrame.ownship(
                        latRaw: 0x1B0000, lonRaw: 0xA80000, trackRaw: raw)))
            #expect(reader.track == expected)
        }
    }

    @Test("A single flipped bit fails CRC validation and is dropped")
    func testFlippedBitFailsCRC() {
        let (reader, location) = makeReader()
        seed(location)

        var frame = Array(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000)))
        // Byte 0 is the opening flag; index 6 is inside the latitude field.
        frame[6] ^= 0x01

        reader.processGDL90Data(Data(frame))

        #expect(reader.latitude == 0)  // untouched initial value
        #expect(reader.altitude == nil)
        expectUnchanged(location)
    }

    @Test("Payload bytes 0x7E and 0x7D are unstuffed before parsing")
    func testByteUnstuffing() {
        let (reader, location) = makeReader()

        // 0x7E / 0x7D in the address and call sign fields: if unstuffing were
        // wrong, everything after them would be misaligned.
        let payload = GDL90TestFrame.ownship(
            latRaw: 0x1B0000,
            lonRaw: 0xA80000,
            address: [0x7E, 0x7D, 0x7E],
            callSign: [0x7D, 0x7E, 0x5D, 0x5E, 0x7D, 0x7D, 0x20, 0x20]
        )
        let frame = GDL90TestFrame.frame(payload)
        // Sanity check: the frame really does carry escape sequences.
        #expect(frame.dropFirst().dropLast().contains(0x7D))

        reader.processGDL90Data(frame)

        #expect(reader.latitude == 37.96875)
        #expect(reader.longitude == -123.75)
        #expect(reader.altitude == 5250)
        #expect(reader.groundSpeed == 120)
        #expect(reader.track == 90.0)
        #expect(location.latitude == 37.96875)
    }

    @Test("Altitude 0xFFF means unavailable and blocks the location update")
    func testInvalidAltitude() {
        let (reader, location) = makeReader()
        seed(location)

        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(
                    latRaw: 0x1B0000, lonRaw: 0xA80000, altRaw: 0xFFF)))

        // The report itself is decoded and published...
        #expect(reader.latitude == 37.96875)
        #expect(reader.altitude == nil)
        // ...but with no usable altitude nothing reaches the guidance display.
        expectUnchanged(location)
    }

    @Test("Velocity 0xFFF means unavailable")
    func testInvalidVelocity() {
        let (reader, location) = makeReader()

        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(
                    latRaw: 0x1B0000, lonRaw: 0xA80000, velocityRaw: 0xFFF)))

        #expect(reader.groundSpeed == 0)  // published as 0 when unknown
        #expect(location.latitude == 37.96875)
        #expect(location.groundSpeed == nil)  // but never as a real speed
    }

    @Test("Altitude decoding covers the ends of the 12-bit range")
    func testAltitudeRange() {
        let (reader, _) = makeReader()
        let cases: [(UInt16, Double)] = [
            (0x000, -1000), (0x028, 0), (0x0FA, 5250), (0xFFE, 101_350),
        ]
        cases.forEach { raw, expected in
            reader.processGDL90Data(
                GDL90TestFrame.frame(
                    GDL90TestFrame.ownship(
                        latRaw: 0x1B0000, lonRaw: 0xA80000, altRaw: raw)))
            #expect(reader.altitude == expected)
        }
    }

    // MARK: Sign extension

    @Test("Negative latitude/longitude sign-extend at the 0x800000 boundary")
    func testNegativeCoordinateSignExtension() {
        let (reader, _) = makeReader()

        // 0xC00000 -> -4_194_304 -> -90.0; 0x800000 -> -8_388_608 -> -180.0
        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0xC00000, lonRaw: 0x800000)))

        #expect(reader.latitude == -90.0)
        #expect(reader.longitude == -180.0)
    }

    @Test("0x7FFFFF stays positive (no spurious sign extension)")
    func testPositiveBoundaryIsNotSignExtended() {
        let (reader, _) = makeReader()

        // 0x000001 -> smallest positive step; 0x7FFFFF -> 180 - 180/2^23
        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x000001, lonRaw: 0x7FFFFF)))

        #expect(abs(reader.latitude - 180.0 / 8_388_608.0) < 1e-12)
        #expect(abs(reader.longitude - (180.0 - 180.0 / 8_388_608.0)) < 1e-9)
        #expect(reader.longitude < 180.0)
    }

    @Test("Latitude outside +/-90 (0x800000) is rejected")
    func testOutOfRangeLatitudeRejected() {
        let (reader, location) = makeReader()
        seed(location)

        // The 24-bit latitude field spans +/-180, so a corrupt value can land
        // outside the valid latitude range.
        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x800000, lonRaw: 0x000000)))

        #expect(reader.latitude == 0)  // untouched initial value
        expectUnchanged(location)
    }

    // MARK: Validity indicators

    @Test("NIC 0 (no fix, lat/lon 0) is published but not used for guidance")
    func testNICZeroRejected() {
        let (reader, location) = makeReader()
        seed(location)

        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0, lonRaw: 0, nic: 0)))

        #expect(reader.nic == 0)
        expectUnchanged(location)  // not sent to Null Island
    }

    @Test("NIC is decoded from the upper nibble of byte 13")
    func testNICDecoded() {
        let (reader, location) = makeReader()

        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000, nic: 1)))

        #expect(reader.nic == 1)
        #expect(location.latitude == 37.96875)
    }

    @Test(
        "Only a true track reaches GenericLocation",
        arguments: [
            (UInt8(0), GDL90TrackType.notValid, false),
            (UInt8(1), GDL90TrackType.trueTrack, true),
            (UInt8(2), GDL90TrackType.magneticHeading, false),
            (UInt8(3), GDL90TrackType.trueHeading, false),
        ])
    func testTrackType(raw: UInt8, type: GDL90TrackType, usable: Bool) {
        let (reader, location) = makeReader()
        seed(location)

        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000, trackType: raw)))

        #expect(reader.trackType == type)
        #expect(reader.track == 90.0)  // raw value always published for debugging
        #expect(location.latitude == 37.96875)  // position still used
        #expect(location.track == (usable ? 90.0 : nil))
    }

    @Test("Heartbeat GPS position valid bit is decoded")
    func testHeartbeatGPSValid() {
        let (reader, location) = makeReader()
        seed(location)
        #expect(reader.deviceGPSValid == nil)

        reader.processGDL90Data(GDL90TestFrame.frame(GDL90TestFrame.heartbeat(gpsValid: true)))
        #expect(reader.deviceGPSValid == true)

        reader.processGDL90Data(GDL90TestFrame.frame(GDL90TestFrame.heartbeat(gpsValid: false)))
        #expect(reader.deviceGPSValid == false)

        // Status only: a heartbeat never touches the guidance location
        expectUnchanged(location)
    }

    @Test("Spec heartbeat example decodes as GPS position valid")
    func testSpecHeartbeat() {
        let (reader, _) = makeReader()
        reader.processGDL90Data(
            GDL90TestFrame.frame([0x00, 0x81, 0x41, 0xDB, 0xD0, 0x08, 0x02]))
        #expect(reader.deviceGPSValid == true)
    }

    // MARK: Geometric altitude (message 11)

    @Test("Message 11 decodes a positive geometric altitude")
    func testGeometricAltitudePositive() {
        let (reader, _) = makeReader()

        // 200 * 5 = 1000 ft
        reader.processGDL90Data(
            GDL90TestFrame.frame(GDL90TestFrame.geometricAltitude(raw: 200)))

        #expect(reader.geometricAltitude == 1000)
        #expect(reader.geometricAltitudeTime != nil)
    }

    @Test("Message 11 decodes a negative geometric altitude")
    func testGeometricAltitudeNegative() {
        let (reader, _) = makeReader()

        // 0xFF9C -> -100 -> -500 ft (below sea level, e.g. Dead Sea airstrips)
        reader.processGDL90Data(
            GDL90TestFrame.frame(GDL90TestFrame.geometricAltitude(raw: -100)))

        #expect(reader.geometricAltitude == -500)
    }

    @Test("Fresh message 11 altitude is preferred over pressure altitude")
    func testGeometricAltitudePreferred() {
        let (reader, location) = makeReader()

        reader.processGDL90Data(
            GDL90TestFrame.frame(GDL90TestFrame.geometricAltitude(raw: 1200)))
        reader.processGDL90Data(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000)))

        #expect(reader.altitude == 5250)  // pressure altitude still published
        #expect(reader.usingGeometricAltitude == true)
        #expect(location.altitude == 6000)  // 1200 * 5
    }

    @Test("Truncated message 11 is ignored")
    func testTruncatedGeometricAltitude() {
        let (reader, _) = makeReader()

        reader.processGDL90Data(GDL90TestFrame.frame([11, 0x00]))

        #expect(reader.geometricAltitude == 0)
        #expect(reader.geometricAltitudeTime == nil)
    }

    // MARK: Framing edge cases

    @Test("Frame without a closing flag is dropped")
    func testUnterminatedFrame() {
        let (reader, location) = makeReader()
        seed(location)

        reader.processGDL90Data(
            GDL90TestFrame.unterminatedFrame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000)))

        #expect(reader.latitude == 0)
        expectUnchanged(location)
    }

    @Test("Ownship report shorter than 28 bytes is ignored")
    func testShortOwnshipReport() {
        let (reader, location) = makeReader()
        seed(location)

        // Valid framing and CRC, payload cut off mid-message.
        let short = Array(
            GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000).prefix(20))
        reader.processGDL90Data(GDL90TestFrame.frame(short))

        #expect(reader.latitude == 0)
        expectUnchanged(location)
    }

    @Test("Two frames in one datagram are both processed")
    func testTwoFramesInOneDatagram() {
        let (reader, location) = makeReader()

        let datagram =
            GDL90TestFrame.frame(GDL90TestFrame.geometricAltitude(raw: 1200))
            + GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000))

        reader.processGDL90Data(datagram)

        #expect(reader.geometricAltitude == 6000)
        #expect(reader.latitude == 37.96875)
        #expect(reader.altitude == 5250)
        #expect(location.altitude == 6000)  // geometric wins, it just arrived
    }

    @Test("Two frames sharing one flag byte are both processed")
    func testTwoFramesSharingAFlag() {
        let (reader, _) = makeReader()

        // ...7E <msg 11> 7E <msg 10> 7E: the closing flag of the first frame
        // is the opening flag of the second.
        let first = GDL90TestFrame.frame(GDL90TestFrame.geometricAltitude(raw: 1200))
        let second = GDL90TestFrame.frame(
            GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000))
        let datagram = first + second.dropFirst()

        reader.processGDL90Data(datagram)

        #expect(reader.geometricAltitude == 6000)
        #expect(reader.latitude == 37.96875)
    }

    @Test("A good frame after a corrupt one is still processed")
    func testGoodFrameAfterCorruptFrame() {
        let (reader, _) = makeReader()

        var corrupt = Array(
            GDL90TestFrame.frame(
                GDL90TestFrame.ownship(latRaw: 0x1B0000, lonRaw: 0xA80000)))
        corrupt[6] ^= 0x01
        let datagram =
            Data(corrupt)
            + GDL90TestFrame.frame(GDL90TestFrame.geometricAltitude(raw: 200))

        reader.processGDL90Data(datagram)

        #expect(reader.latitude == 0)  // corrupt frame still rejected
        #expect(reader.geometricAltitude == 1000)
    }

    @Test("Unknown message IDs are ignored")
    func testUnknownMessageID() {
        let (reader, location) = makeReader()
        seed(location)

        reader.processGDL90Data(GDL90TestFrame.frame([0x65, 0x00, 0x01, 0x02, 0x03]))
        reader.processGDL90Data(GDL90TestFrame.frame([20, 0x01, 0x02, 0x03, 0x04]))

        #expect(reader.latitude == 0)
        expectUnchanged(location)
    }

    @Test(
        "Garbage and empty data are ignored without crashing",
        arguments: [
            Data(),
            Data([0x7E]),
            Data([0x7E, 0x7E, 0x7E]),
            Data([0x7E, 0x7D, 0x7E]),  // escape with nothing to escape
            Data([0x7E, 0x0A, 0x7D]),  // dangling escape, no closing flag
            Data([0x7E, 0x0A, 0x00, 0x7E]),  // too short to hold a CRC
            Data(repeating: 0xAA, count: 64),  // no framing at all
            Data((0...255).map { UInt8($0) }),
        ])
    func testGarbageData(data: Data) {
        let (reader, location) = makeReader()
        seed(location)

        reader.processGDL90Data(data)

        #expect(reader.latitude == 0)
        #expect(reader.altitude == nil)
        expectUnchanged(location)
    }
}
