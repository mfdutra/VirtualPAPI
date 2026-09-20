//
//  LocationTrackerTests.swift
//  VirtualPAPITests
//
//  Tests for the internal GPS source: CoreLocation validity flags and the
//  uncertain-altitude caution.
//

import CoreLocation
import Foundation
import Testing

@testable import VirtualPAPI

// MARK: - Internal GPS Validity Tests

@Suite("Internal GPS Validity Tests")
@MainActor
struct InternalGPSValidityTests {

    /// A tracker wired to a fresh GenericLocation with internal GPS selected,
    /// so a delivered fix is forwarded to the guidance.
    private func makeTracker() -> (
        HighFrequencyLocationTracker, GenericLocation
    ) {
        let settings = AppSettings(defaults: .isolatedForTesting())
        settings.locationSource = .internalGPS
        let genericLocation = GenericLocation()
        genericLocation.reset()
        let tracker = HighFrequencyLocationTracker()
        tracker.appSettings = settings
        tracker.genericLocation = genericLocation
        return (tracker, genericLocation)
    }

    private func fix(
        horizontalAccuracy: CLLocationAccuracy,
        verticalAccuracy: CLLocationAccuracy,
        altitude: CLLocationDistance = 304.8  // 1000 ft
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 37.6213,
                longitude: -122.3790
            ),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: 90,
            speed: 51.44,  // ~100 kt
            timestamp: Date()
        )
    }

    private func deliver(
        _ location: CLLocation,
        to tracker: HighFrequencyLocationTracker
    ) async {
        tracker.locationManager(
            CLLocationManager(),
            didUpdateLocations: [location]
        )
        // The delegate hands the fix to the main queue; let it drain.
        for _ in 0..<10 where tracker.currentLocation == nil {
            await Task.yield()
        }
    }

    @Test("A valid fix updates the guidance")
    func testValidFixAccepted() async {
        let (tracker, genericLocation) = makeTracker()
        await deliver(
            fix(horizontalAccuracy: 5, verticalAccuracy: 8),
            to: tracker
        )

        #expect(tracker.currentLocation != nil)
        #expect(tracker.verticalAccuracy == 8)
        #expect(genericLocation.lastUpdateTime != nil)
        #expect(abs(genericLocation.altitude - 1000) < 1)
    }

    @Test("A fix with invalid altitude is dropped")
    func testNegativeVerticalAccuracyRejected() async {
        let (tracker, genericLocation) = makeTracker()
        // CoreLocation reports altitude 0 with a negative verticalAccuracy;
        // forwarding it would peg the display at "fly up".
        await deliver(
            fix(horizontalAccuracy: 5, verticalAccuracy: -1, altitude: 0),
            to: tracker
        )

        #expect(tracker.currentLocation == nil)
        #expect(genericLocation.lastUpdateTime == nil)
    }

    @Test("A fix with invalid coordinates is dropped")
    func testNegativeHorizontalAccuracyRejected() async {
        let (tracker, genericLocation) = makeTracker()
        await deliver(
            fix(horizontalAccuracy: -1, verticalAccuracy: 8),
            to: tracker
        )

        #expect(tracker.currentLocation == nil)
        #expect(genericLocation.lastUpdateTime == nil)
    }

    @Test("A dropped fix leaves the previous one in place")
    func testRejectedFixKeepsPreviousValues() async {
        let (tracker, genericLocation) = makeTracker()
        await deliver(
            fix(horizontalAccuracy: 5, verticalAccuracy: 8),
            to: tracker
        )
        let firstUpdate = genericLocation.lastUpdateTime

        await deliver(
            fix(horizontalAccuracy: 5, verticalAccuracy: -1, altitude: 0),
            to: tracker
        )

        #expect(genericLocation.lastUpdateTime == firstUpdate)
        #expect(abs(genericLocation.altitude - 1000) < 1)
    }
}

// MARK: - Vertical Accuracy Caution Tests

@Suite("Vertical Accuracy Caution Tests")
@MainActor
struct VerticalAccuracyCautionTests {

    @Test("Accuracy at or under the threshold is not flagged")
    func testGoodAccuracyNotPoor() {
        let tracker = HighFrequencyLocationTracker()
        tracker.verticalAccuracy = 8
        #expect(!tracker.verticalAccuracyIsPoor)

        tracker.verticalAccuracy = HighFrequencyLocationTracker
            .poorVerticalAccuracy
        #expect(!tracker.verticalAccuracyIsPoor)
    }

    @Test("Accuracy over the threshold is flagged")
    func testPoorAccuracyFlagged() {
        let tracker = HighFrequencyLocationTracker()
        tracker.verticalAccuracy = 30
        #expect(tracker.verticalAccuracyIsPoor)
    }

    @Test("Caution text reports metres as feet, rounded to 10")
    func testFormatVerticalAccuracy() {
        // 30 m = 98.4 ft
        #expect(
            ContentView.formatVerticalAccuracy(30) == "GPS ALT \u{00B1}100 ft"
        )
        // 20 m = 65.6 ft
        #expect(
            ContentView.formatVerticalAccuracy(20) == "GPS ALT \u{00B1}70 ft"
        )
    }
}
