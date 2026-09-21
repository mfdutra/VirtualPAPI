//
//  InternalLocationDebugView.swift
//  VirtualPAPI
//
//  Everything CoreLocation reports for the internal GPS, including fixes the
//  guidance drops as invalid.
//

import CoreLocation
import SwiftUI

struct InternalLocationDebugView: View {
    @EnvironmentObject var tracker: HighFrequencyLocationTracker
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        // Refresh once a second so the "age" rows keep counting
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                statusSection(now: context.date)
                fixSection(now: context.date)
                headingSection(now: context.date)
                configurationSection
            }
        }
        .navigationTitle("Internal GPS Debug")
        .onAppear {
            tracker.refreshLocationServicesEnabled()
            tracker.startHeadingUpdates()
        }
        .onDisappear {
            tracker.stopHeadingUpdates()
        }
    }

    // MARK: - Sections

    private func statusSection(now: Date) -> some View {
        Section("Status") {
            if settings.locationSource != .internalGPS {
                Text(
                    "Internal GPS is not the selected location source. It keeps running, but its fixes don't feed the guidance."
                )
                .font(.footnote)
                .foregroundColor(.orange)
            }

            row(
                "Authorization",
                Self.describe(tracker.authorizationStatus),
                color: Self.isAuthorized(tracker.authorizationStatus)
                    ? .green : .red
            )
            row(
                "Accuracy Authorization",
                tracker.accuracyAuthorization == .fullAccuracy
                    ? "Full" : "Reduced",
                color: tracker.accuracyAuthorization == .fullAccuracy
                    ? .green : .red
            )
            row(
                "Location Services",
                tracker.locationServicesEnabled.map { $0 ? "On" : "Off" }
                    ?? "—",
                color: tracker.locationServicesEnabled == false
                    ? .red : .secondary
            )
            row("Tracking Requested", tracker.isTracking ? "Yes" : "No")
            row("Updating Location", tracker.isUpdatingLocation ? "Yes" : "No")
            row(
                "Paused by System",
                tracker.updatesPaused ? "Yes" : "No",
                color: tracker.updatesPaused ? .orange : .secondary
            )
            row("Fixes Accepted", "\(tracker.acceptedFixCount)")
            row(
                "Fixes Rejected",
                "\(tracker.rejectedFixCount)",
                color: tracker.rejectedFixCount > 0 ? .orange : .secondary
            )
            if let error = tracker.lastError, let time = tracker.lastErrorTime {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last Error")
                    Text("\(error) · \(Self.formatAge(time, now: now))")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .monospaced()
                }
            } else {
                row("Last Error", "None")
            }
        }
    }

    @ViewBuilder
    private func fixSection(now: Date) -> some View {
        Section("Last Fix (raw from CoreLocation)") {
            if let location = tracker.lastRawLocation {
                if let reason = tracker.lastRejectionReason {
                    row("Guidance", "Rejected", color: .red)
                    Text(reason)
                        .font(.footnote)
                        .foregroundColor(.red)
                } else {
                    row("Guidance", "Accepted", color: .green)
                }

                row("Age", Self.formatAge(location.timestamp, now: now))
                row(
                    "Timestamp",
                    location.timestamp.formatted(
                        .dateTime.hour().minute().second()
                    )
                )
                row(
                    "Latitude",
                    String(format: "%.6f°", location.coordinate.latitude)
                )
                row(
                    "Longitude",
                    String(format: "%.6f°", location.coordinate.longitude)
                )
                row(
                    "Horizontal Accuracy",
                    Self.formatAccuracy(location.horizontalAccuracy),
                    color: location.horizontalAccuracy < 0 ? .red : .secondary
                )
                row("Altitude (MSL)", Self.formatAltitude(location.altitude))
                row(
                    "Ellipsoidal Altitude",
                    Self.formatAltitude(location.ellipsoidalAltitude)
                )
                row(
                    "Vertical Accuracy",
                    Self.formatAccuracy(location.verticalAccuracy),
                    color: location.verticalAccuracy < 0
                        ? .red
                        : (location.verticalAccuracy
                            > HighFrequencyLocationTracker.poorVerticalAccuracy
                            ? .orange : .secondary)
                )
                row(
                    "Speed",
                    location.speed < 0
                        ? "invalid (\(location.speed))"
                        : String(
                            format: "%.1f m/s (%.1f kt)",
                            location.speed,
                            location.speed * 1.9438445
                        ),
                    color: location.speed < 0 ? .red : .secondary
                )
                row(
                    "Speed Accuracy",
                    Self.formatAccuracy(location.speedAccuracy, unit: "m/s")
                )
                row(
                    "Course",
                    location.course < 0
                        ? "invalid (\(location.course))"
                        : String(format: "%.1f°", location.course),
                    color: location.course < 0 ? .red : .secondary
                )
                row(
                    "Course Accuracy",
                    Self.formatAccuracy(location.courseAccuracy, unit: "°")
                )
                row("Floor", location.floor.map { "\($0.level)" } ?? "—")
                row(
                    "Simulated by Software",
                    Self.formatFlag(
                        location.sourceInformation?.isSimulatedBySoftware
                    )
                )
                row(
                    "Produced by Accessory",
                    Self.formatFlag(
                        location.sourceInformation?.isProducedByAccessory
                    )
                )
            } else {
                Text("No fix received yet")
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func headingSection(now: Date) -> some View {
        Section("Heading (compass)") {
            if !CLLocationManager.headingAvailable() {
                Text("Not available on this device")
                    .foregroundColor(.secondary)
            } else if let heading = tracker.heading {
                row("Age", Self.formatAge(heading.timestamp, now: now))
                row(
                    "Magnetic Heading",
                    String(format: "%.1f°", heading.magneticHeading)
                )
                row(
                    "True Heading",
                    heading.trueHeading < 0
                        ? "invalid (\(heading.trueHeading))"
                        : String(format: "%.1f°", heading.trueHeading),
                    color: heading.trueHeading < 0 ? .red : .secondary
                )
                row(
                    "Heading Accuracy",
                    Self.formatAccuracy(heading.headingAccuracy, unit: "°")
                )
                row(
                    "Magnetic Field (x, y, z)",
                    String(
                        format: "%.1f, %.1f, %.1f µT",
                        heading.x,
                        heading.y,
                        heading.z
                    )
                )
            } else {
                Text("Waiting for heading…")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var configurationSection: some View {
        Section("Manager Configuration") {
            row(
                "Desired Accuracy",
                Self.describeDesiredAccuracy(tracker.desiredAccuracy)
            )
            row(
                "Distance Filter",
                tracker.distanceFilter == kCLDistanceFilterNone
                    ? "None" : String(format: "%.0f m", tracker.distanceFilter)
            )
            row("Activity Type", Self.describe(tracker.activityType))
            row(
                "Pauses Automatically",
                tracker.pausesLocationUpdatesAutomatically ? "Yes" : "No"
            )
            row(
                "Heading Filter",
                tracker.headingFilter == kCLHeadingFilterNone
                    ? "None" : String(format: "%.0f°", tracker.headingFilter)
            )
        }
    }

    private func row(
        _ label: String,
        _ value: String,
        color: Color = .secondary
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .monospaced()
        }
    }

    // MARK: - Formatting

    /// CoreLocation accuracies are negative when the value is invalid
    static func formatAccuracy(
        _ accuracy: Double,
        unit: String = "m"
    ) -> String {
        guard accuracy >= 0 else {
            return "invalid (\(accuracy.formatted()))"
        }
        let separator = unit == "°" ? "" : " "
        return String(format: "±%.1f", accuracy) + separator + unit
    }

    static func formatAltitude(_ meters: Double) -> String {
        String(format: "%.1f m (%.0f ft)", meters, meters * 3.2808399)
    }

    static func formatFlag(_ flag: Bool?) -> String {
        flag.map { $0 ? "Yes" : "No" } ?? "—"
    }

    static func formatAge(_ date: Date, now: Date) -> String {
        String(format: "%.0f s", max(0, now.timeIntervalSince(date)))
    }

    static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not Determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "When In Use"
        @unknown default: "Unknown (\(status.rawValue))"
        }
    }

    static func describe(_ activityType: CLActivityType) -> String {
        switch activityType {
        case .other: "Other"
        case .automotiveNavigation: "Automotive Navigation"
        case .fitness: "Fitness"
        case .otherNavigation: "Other Navigation"
        case .airborne: "Airborne"
        @unknown default: "Unknown (\(activityType.rawValue))"
        }
    }

    static func describeDesiredAccuracy(_ accuracy: CLLocationAccuracy)
        -> String
    {
        switch accuracy {
        case kCLLocationAccuracyBestForNavigation: "Best for Navigation"
        case kCLLocationAccuracyBest: "Best"
        case kCLLocationAccuracyNearestTenMeters: "Nearest 10 m"
        case kCLLocationAccuracyHundredMeters: "100 m"
        case kCLLocationAccuracyKilometer: "1 km"
        case kCLLocationAccuracyThreeKilometers: "3 km"
        case kCLLocationAccuracyReduced: "Reduced"
        default: String(format: "%.0f m", accuracy)
        }
    }
}

#Preview {
    NavigationStack {
        InternalLocationDebugView()
            .environmentObject(HighFrequencyLocationTracker())
            .environmentObject(AppSettings())
    }
}
