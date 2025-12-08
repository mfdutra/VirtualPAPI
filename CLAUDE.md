# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VirtualPAPI is an iOS SwiftUI application for aviation navigation, specifically designed to provide visual approach guidance. The app displays configurable visual approach indicators (glide slope or PAPI/VASI style) and can receive location data from three sources: the device's internal GPS, X-Plane flight simulator via UDP, or GDL90-compatible devices via UDP.

## Build & Development Commands

### Building the Project
```bash
# Build for iOS simulator
xcodebuild -scheme VirtualPAPI -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for device (requires proper code signing)
xcodebuild -scheme VirtualPAPI -destination 'generic/platform=iOS' build

# Clean build artifacts
xcodebuild -scheme VirtualPAPI clean
```

### Running Tests
```bash
# Run unit tests
xcodebuild test -scheme VirtualPAPI -destination 'platform=iOS Simulator,name=iPhone 17'

# Run specific test target
xcodebuild test -scheme VirtualPAPI -only-testing:VirtualPAPITests -destination 'platform=iOS Simulator,name=iPhone 17'

# Run UI tests
xcodebuild test -scheme VirtualPAPI -only-testing:VirtualPAPIUITests -destination 'platform=iOS Simulator,name=iPhone 17'
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

**Database Management:**
- `DatabaseManager` (singleton) handles SQLite operations
- Database copied from bundle to Documents directory on first launch
- Supports remote database updates via `downloadRemoteDatabase()` method
- Provides query methods: `getAirport(ident:)`, `searchAirports()`, `getRunways(airportId:)`
- Returns table counts for diagnostics

## Architecture

### State Management Pattern
The app uses SwiftUI's `@StateObject` and `@EnvironmentObject` pattern for global state:

1. **VirtualPAPIApp.swift** (app entry point) creates six core state objects:
   - `AppSettings`: User preferences (location source, visualization type, debug info, favorites, smoothing)
   - `GenericLocation`: Abstract location provider consumed by UI, handles calculations
   - `XGPSDataReader`: UDP listener for X-Plane GPS data (port 49002)
   - `GDL90Reader`: UDP listener for GDL90-compatible GPS devices (port 4000)
   - `AirportSelection`: Selected airport, runway, and approach parameters
   - `HighFrequencyLocationTracker`: CoreLocation-based GPS tracker for internal GPS

2. These are injected into the view hierarchy via `.environmentObject()` and accessed with `@EnvironmentObject` in child views.

3. Location sources are managed centrally in VirtualPAPIApp:
   - `startListenerForSource()` and `stopListenerForSource()` methods toggle between sources
   - Only one location source is active at a time based on `AppSettings.locationSource`
   - The active source updates `GenericLocation` which the UI observes

### Location Data Flow
The app supports three location sources, selectable via `AppSettings.locationSource` enum:

**Internal GPS** (`LocationSource.internalGPS`):
- `HighFrequencyLocationTracker` uses CoreLocation with high-frequency polling
- Instantiated in VirtualPAPIApp and starts tracking on app launch (VirtualPAPIApp.swift:40-41)
- Updates `GenericLocation` with position, speed, and track data
- Runs continuously but only updates GenericLocation when selected as active source

**X-Plane Simulator** (`LocationSource.xPlane`):
- `XGPSDataReader` listens on UDP port 49002 for XGPS format packets
- Parses lat/lon/alt/speed/track from comma-separated ASCII data (XGPSDataReader.swift:128-151)
- Converts altitude from meters to feet (×3.2808399) and speed from m/s to knots (×1.9438445)
- Updates `GenericLocation` only when X-Plane is the selected source (XGPSDataReader.swift:117)

**GDL90 Devices** (`LocationSource.gdl90`):
- `GDL90Reader` listens on UDP port 4000 for GDL90-formatted packets
- Implements full GDL90 protocol parsing with CRC validation
- Parses Message ID 10 (Ownship Report) for position, altitude, speed, and track
- Parses Message ID 11 (Ownship Geometric Altitude) for geometric altitude
- Broadcasts UDP heartbeat on port 63093 to advertise availability to GDL90 devices
- Updates `GenericLocation` only when GDL90 is the selected source (GDL90Reader.swift:181)

**GenericLocation** acts as the single source of truth for the UI and contains:
- Current position (lat/lon/alt), speed, and track
- Vincenty's formula implementation for accurate distance calculations on WGS84 ellipsoid (GenericLocation.swift:275-366)
- Active glide slope deviation calculations with configurable descent angle
- Distance and bearing calculations to selected runway
- Exponential moving average (EMA) smoothing for glide slope with configurable alpha
- Staleness detection (marks location stale if no updates for 5+ seconds)
- PAPI color calculation for 4-light PAPI display

### UI Architecture

**Main Views:**

- **ContentView.swift**: Primary navigation and display view
  - Shows selected airport/runway information with distance-to-go (DTG) and angle
  - Displays bearing indicator (arrow) showing direction to destination
  - Switches between GlideSlopeView and PapiView based on `AppSettings.visualization`
  - Double-tap to toggle between visualization modes
  - Favorite airports quick-access section (scrollable horizontal list)
  - Navigation to AirportSelectionView and SettingsView
  - Location staleness warning when GPS signal is lost
  - Debug info display (lat/lon/alt/speed/track/source) when enabled

- **GlideSlopeView.swift**: ILS-style glide slope indicator
  - GeometryReader-based visual display with animated diamond indicator
  - Indicator position based on `genericLocation.gsOffset` or `genericLocation.smoothedGsOffset`
  - Vertical position shows deviation from configured descent angle (default 3°)
  - Supports configurable smoothing via EMA

- **PapiView.swift**: PAPI-style 4-light visual indicator
  - Four horizontal lights that change color based on approach angle
  - Red lights indicate too low, white lights indicate on or above glide slope
  - Uses `genericLocation.papiColors` array for interpolated colors
  - Standard PAPI configuration (2 red / 2 white = on glide slope)

- **AirportSelectionView.swift**: Airport and runway selection interface
  - Search functionality for airports by identifier or name
  - Displays airport details (elevation, coordinates)
  - Runway selection with visual layout
  - Configurable descent angle (default 3.0°)
  - Configurable aiming point (default 500 ft from threshold)
  - Favorite airport toggle (star icon)
  - Accounts for displaced thresholds in target calculation

- **SettingsView.swift**: Configuration screen
  - Location source picker (Internal GPS / X-Plane / GDL90)
  - Visualization type picker (Glide Slope / PAPI)
  - Responsiveness slider (EMA alpha: Smooth/Medium/Fast/Instantaneous)
  - Network information (local IP address for UDP troubleshooting)
  - Aviation database info (last modified date, airport/runway counts)
  - Database update functionality (downloads latest data from remote source)
  - Debug mode toggle
  - Links to debug views (GDL90, Generic Location, Destination Map)

**Debug Views:**

- **GDL90DebugView.swift**: Real-time GDL90 protocol diagnostics
- **GenericLocationDebugView.swift**: Location calculation diagnostics
- **DestinationMapView.swift**: Map visualization of destination and current position

### Data Models

**Core Models (Structs.swift):**
- `Airport`: Basic airport info (ident, name, coordinates, elevation)
- `Runway`: Runway-specific data (heading, displaced threshold, dimensions)

These match the SQLite schema in `scripts/aviation.db`.

**Enums (AppSettings.swift):**
- `LocationSource`: Internal GPS / X-Plane / GDL90 (CaseIterable, Identifiable)
- `VisualizationType`: Glide Slope / PAPI (CaseIterable, Identifiable)

**Settings and State:**
- `AppSettings`: Observable settings object with UserDefaults persistence
  - `locationSource`: Active GPS/simulator source
  - `visualization`: Display mode (glide slope or PAPI)
  - `emaAlpha`: Smoothing factor (0.2 = smooth, 1.0 = instantaneous)
  - `showDebugInfo`: Toggle for debug overlay
  - `favoriteAirports`: Array of airport identifiers
  - Includes migration logic from old `useXPlane` boolean setting

- `AirportSelection`: Observable selection state
  - Selected airport and runway references
  - Descent angle and aiming point configuration
  - Target coordinates (calculated from runway + displaced threshold + aiming point)
  - Favorite airports management with UserDefaults persistence

## Key Implementation Details

### X-Plane UDP Integration
The XGPS protocol expects packets starting with "XGPS" header followed by comma-separated values. The parser (XGPSDataReader.swift:128-151):
1. Validates 41+ byte packets with "XGPS" header
2. Extracts longitude (component 1), latitude (component 2), altitude in meters (component 3), track in degrees (component 4), speed in m/s (component 5)
3. Converts altitude from meters to feet (×3.2808399)
4. Converts speed from m/s to knots (×1.9438445)
5. Updates both `XGPSDataReader` and `GenericLocation` states (only when X-Plane is selected source)

### GDL90 Protocol Integration
The GDL90 protocol is a standard aviation data link protocol used by many portable GPS and ADS-B receivers. The implementation (GDL90Reader.swift):

**Framing and Validation:**
- Messages framed with 0x7E flag bytes
- Byte stuffing: 0x7D escape byte followed by XOR 0x20
- CRC-16-CCITT validation with table-driven lookup (polynomial 0x1021)
- Validates CRC before processing any message

**Message Parsing:**
- Message ID 10 (Ownship Report): Position, pressure altitude, ground speed, track
  - 24-bit signed lat/lon with LSB = 180/2^23 degrees
  - 12-bit altitude with 25 ft resolution, -1000 ft offset
  - 12-bit velocity with 1 knot resolution (0xFFF = invalid)
  - 8-bit track with LSB = 360/256 = 1.40625 degrees
- Message ID 11 (Ownship Geometric Altitude): 16-bit signed with 5 ft resolution

**Device Discovery:**
- Broadcasts UDP heartbeat on port 63093 every 5 seconds
- JSON payload: `{"App": "VirtualPAPI", "GDL90": {"port": 4000}}`
- Allows GDL90 devices to discover and connect to the app

### Airport Selection and Target Calculation
The `AirportSelection` class (AirportSelection.swift) manages destination configuration:
- Stores selected airport and runway
- Calculates final aiming point using `calculateAimingPoint()` (AirportSelection.swift:94-147)
- Accounts for displaced threshold + user-specified aiming point (default 500 ft)
- Uses great circle calculation to project target point along runway heading
- Updates `GenericLocation` with target coordinates for distance/bearing calculations

### Glide Slope Calculation
The glide slope deviation logic (GenericLocation.swift:222-244):
- Configurable descent angle (default 3.0°, stored in `AirportSelection.descentAngle`)
- Calculates actual angle: `atan((altitude - targetElevation) / distanceInFeet) * 180 / π`
- Deviation = actual angle - desired descent angle
- Positive deviation = aircraft above glide slope (fly down)
- Exponential Moving Average (EMA) smoothing applied: `EMA_new = alpha * current + (1 - alpha) * EMA_previous`
  - Alpha configurable via `AppSettings.emaAlpha` (0.2 = smooth, 1.0 = instantaneous)
- Display offset calculation (GenericLocation.swift:246-258):
  - Full scale deviation = 0.7° (±45% of display height = ±1.55555°)
  - `gsOffset = angleDeviation / 1.55555`, clamped to ±0.45
- PAPI color calculation (GenericLocation.swift:260-273):
  - Position shifts ±0.5 while deviation shifts ±0.7 (factor of 1.4)
  - Each light interpolates smoothly between red and white

### High-Precision Distance Calculations
`GenericLocation.distance()` implements Vincenty's inverse formula for WGS84 ellipsoid (GenericLocation.swift:275-366), falling back to Haversine for antipodal points. Returns nautical miles.

The `heading()` method (GenericLocation.swift:107-139) calculates true bearing from current position to destination using the forward azimuth formula, returning 0-360° where 0° is North.

Relative bearing calculation (GenericLocation.swift:194-220):
- When track data is available, calculates where the destination is relative to current heading
- Positive values = turn right, negative = turn left
- Normalized to ±180° range for intuitive display

## Development Notes

### SwiftUI Previews
Most views include `#Preview` macros for Xcode canvas previews. When modifying views, ensure all required environment objects are provided in previews:
```swift
#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(GenericLocation())
        .environmentObject(XGPSDataReader())
        .environmentObject(GDL90Reader())
        .environmentObject(AirportSelection())
        .environmentObject(HighFrequencyLocationTracker())
}
```

Note: Not all views require all environment objects. Check the view's `@EnvironmentObject` declarations to determine which are needed.

### Concurrency
- `XGPSDataReader` and `GDL90Reader` use `@MainActor` to ensure all UI updates happen on main thread
- UDP networking happens on background queues: `DispatchQueue(label: "xgps-udp-queue")` and `DispatchQueue(label: "gdl90-udp-queue")`
- Location updates use `Task { @MainActor in ... }` for thread-safe UI updates
- Database operations in `DatabaseManager` are async/await capable for non-blocking updates

### Implemented Features
The app includes fully implemented features for real-world aviation use:

**Airport/Runway Database:**
- SQLite database with airports and runways from OurAirports.com
- Search and selection UI with favorites management
- Automatic database updates via Settings (downloads remote database)
- Displaced threshold and aiming point calculations

**Multi-Source Location:**
- Three independent location sources (GPS, X-Plane, GDL90)
- Automatic source switching with proper cleanup
- Location staleness detection (5-second timeout)

**Visual Approach Guidance:**
- Dual visualization modes (ILS-style glide slope, PAPI)
- Configurable descent angles (not just standard 3°)
- Configurable smoothing/responsiveness
- Real-time distance, bearing, and angle calculations

**User Experience:**
- Persistent settings and favorites (UserDefaults)
- Prevents screen sleep during use (UIApplication.shared.isIdleTimerDisabled)
- Debug views for troubleshooting GPS and protocol issues

## Project Configuration
- **Deployment Target**: iOS 26.0
- **Development Team**: B4F7YCNRD9
- **Bundle ID**: com.mfdutra.VirtualPAPI
- **Swift Version**: 5.0
- **Supported Devices**: iPhone and iPad (universal)
