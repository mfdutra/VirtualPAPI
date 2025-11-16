# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VisualApproach is an iOS SwiftUI application for aviation navigation, specifically designed to provide visual approach guidance. The app displays a glide slope indicator (similar to a PAPI/VASI) and can receive location data from either the device's GPS or X-Plane flight simulator via UDP.

## Build & Development Commands

### Building the Project
```bash
# Build for iOS simulator
xcodebuild -scheme VisualApproach -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build for device (requires proper code signing)
xcodebuild -scheme VisualApproach -destination 'generic/platform=iOS' build

# Clean build artifacts
xcodebuild -scheme VisualApproach clean
```

### Running Tests
```bash
# Run unit tests
xcodebuild test -scheme VisualApproach -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test target
xcodebuild test -scheme VisualApproach -only-testing:VisualApproachTests -destination 'platform=iOS Simulator,name=iPhone 16'

# Run UI tests
xcodebuild test -scheme VisualApproach -only-testing:VisualApproachUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Database Generation
The `scripts/` directory contains aviation data from ourairports.com:
```bash
# Regenerate the SQLite database from CSV files
cd scripts
./gen_sqlite.py
```

This creates `aviation.db` with airports and runways tables. The script processes:
- `airports.csv`: Airport locations and elevations
- `runways.csv`: Runway coordinates, headings, and displaced thresholds

## Architecture

### State Management Pattern
The app uses SwiftUI's `@StateObject` and `@EnvironmentObject` pattern for global state:

1. **VisualApproachApp.swift** (app entry point) creates three core state objects:
   - `AppSettings`: User preferences (X-Plane mode, debug info display)
   - `GenericLocation`: Abstract location provider consumed by UI
   - `XGPSDataReader`: UDP listener for X-Plane GPS data

2. These are injected into the view hierarchy via `.environmentObject()` and accessed with `@EnvironmentObject` in child views.

### Location Data Flow
The app supports dual location sources with this architecture:

**Native iOS GPS:**
- `HighFrequencyLocationTracker` uses CoreLocation with high-frequency polling
- Directly updates its `@Published` properties
- Currently instantiated in ContentView but not connected to `GenericLocation`

**X-Plane Simulator:**
- `XGPSDataReader` listens on UDP port 49002 for XGPS format packets
- Parses lat/lon/alt from comma-separated ASCII data
- Updates both its own properties AND `GenericLocation` properties (see line XGPSDataReader.swift:125-127)
- Enabled/disabled via `AppSettings.useXPlane` toggle

**GenericLocation** acts as the single source of truth for the UI and contains:
- Current position (lat/lon/alt)
- Vincenty's formula implementation for accurate distance calculations on WGS84 ellipsoid
- Glide slope deviation calculations (commented out, awaiting airport selection feature)

### UI Architecture
- **ContentView.swift**: Main view with glide slope indicator
  - GeometryReader-based visual display showing deviation from 3° glide slope
  - Diamond indicator animates vertically based on `genericLocation.gsOffset`
  - Debug info display toggled by settings

- **SettingsView.swift**: Configuration screen
  - X-Plane toggle
  - Local IP address display for network troubleshooting
  - Debug mode toggle

### Data Models (Structs.swift)
- `Airport`: Basic airport info (ident, name, coordinates, elevation)
- `Runway`: Runway-specific data (heading, displaced threshold, dimensions)

These match the SQLite schema in `scripts/aviation.db`.

## Key Implementation Details

### X-Plane UDP Integration
The XGPS protocol expects packets starting with "XGPS" header followed by comma-separated values. The parser (XGPSDataReader.swift:106-128):
1. Validates 41+ byte packets with "XGPS" header
2. Extracts longitude (component 1), latitude (component 2), altitude in meters (component 3)
3. Converts altitude to feet (×3.2808399)
4. Updates both `XGPSDataReader` and `GenericLocation` states

### Glide Slope Calculation
The glide slope deviation logic (GenericLocation.swift:57-72):
- Reference glide slope: 3° (standard ILS)
- 1-dot deviation = 0.15° (fly-up when diamond is low)
- Display clamped to ±0.45 (±3 dots)
- Positive offset = aircraft above glide slope

### High-Precision Distance Calculations
`GenericLocation.distance()` implements Vincenty's inverse formula for WGS84 ellipsoid (GenericLocation.swift:74-157), falling back to Haversine for antipodal points. Returns nautical miles.

## Development Notes

### SwiftUI Previews
Most views include `#Preview` macros for Xcode canvas previews. When modifying views, ensure environment objects are provided in previews:
```swift
#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(GenericLocation())
        .environmentObject(XGPSDataReader())
}
```

### Concurrency
- `XGPSDataReader` uses `@MainActor` to ensure all UI updates happen on main thread
- UDP networking happens on background queue: `DispatchQueue(label: "xgps-udp-queue")`
- Location updates use `DispatchQueue.main.async` for thread safety

### Commented-Out Features
Several features are scaffolded but disabled:
- SwiftData model container (VisualApproachApp.swift:13-24)
- Airport selection and distance-to-destination calculations (ContentView.swift:24-39, GenericLocation.swift:30-48)
- Location tracker debug UI (ContentView.swift:83-113)

These suggest planned features: persistent storage, airport/runway database integration, and enhanced debugging.

## Project Configuration
- **Deployment Target**: iOS 26.0
- **Development Team**: B4F7YCNRD9
- **Bundle ID**: com.mfdutra.VisualApproach
- **Swift Version**: 5.0
- **Supported Devices**: iPhone and iPad (universal)
