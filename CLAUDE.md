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

# Run unit tests natively on an Apple silicon Mac (no simulator), as a "Designed for iPad" app
xcodebuild test -scheme VirtualPAPI -only-testing:VirtualPAPITests -destination 'platform=macOS,arch=arm64,variant=Designed for iPad'
```

When running on the Mac, the `Executed 0 tests` line only counts XCTest tests; Swift Testing reports its results on the `Test run with N tests ... passed` line. The `[AXLoading] ... ScreenTimeUI` errors are harmless macOS noise.

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

Filtering rules applied by the script:
- Runways that are closed, have missing end coordinates or identifiers, or whose two ends share identical coordinates are skipped
- Each runway end is stored as its own row; ends with no elevation data are skipped, so every runway in the database has an elevation
- Airports left with no runways after this filtering are removed
- Missing runway end headings are backfilled: when `le_heading_degT`/`he_heading_degT` is blank, the script stores the true initial great-circle bearing from that end's coordinates to the opposite end's (headings present in the CSV are kept as is). Since runways with identical end coordinates are skipped, every runway in the database has a heading, so `AirportSelection.calculateAimingPoint()` can always apply the displaced threshold and aiming point

**Database Management:**
- `DatabaseManager` (singleton) handles SQLite operations
- Database copied from bundle to Documents directory on first launch
- Supports remote database updates via `downloadRemoteDatabase()` method (TOTP-authenticated, ETag-cached). The update is transactional:
  1. Downloads to a temporary file (`URLSession.download(for:)`), rejecting anything over `maxDatabaseSize` (50 MB; bundled DB is ~3.5 MB) by Content-Length and by actual file size
  2. Validates the staged file (`Documents/aviation.db.download`) with `static func validateDatabase(at:)`: SQLite header magic, read-only open, `PRAGMA integrity_check` == "ok", `airports`/`runways` tables with the columns the app queries, and counts >= `minAirportCount` (5,000) / `minRunwayCount` (15,000) (bundled DB has ~11,400 / ~29,700)
  3. Only then closes the live handle and swaps it in with `FileManager.replaceItemAt`, keeping the previous DB as `aviation.db.bak`; if reopening fails, the backup is restored
  4. Stores the ETag and `last_database_download` only after a successful swap, so a failed update is retried next time
  - Failures surface as `DatabaseError` (a `LocalizedError`: `tooLarge`, `invalidDatabase`, `installFailed`, plus HTTP/URL errors), shown in SettingsView
  - Validation is unit-tested ("Database Validation Tests") against the bundled DB, HTML, empty, truncated, empty-tables and wrong-schema files
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
   - VirtualPAPIApp is the only owner of listener lifecycle; views (including debug views) must not call `startListening()`/`stopListening()`
   - `XGPSDataReader.startListening()` and `GDL90Reader.startListening()` are idempotent (return early if already listening), so a repeated call can't open duplicate sockets/threads or leak the heartbeat timer
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
- Uses a raw BSD socket (not `NWListener`) that never calls `connect()`, so it can't steal broadcast packets from other apps listening on the same port (e.g. ForeFlight) — see "Concurrency" below
- Parses lat/lon/alt/speed/track from comma-separated ASCII data via the pure `nonisolated static func XGPSDataReader.parseXGPS(_:)` (XGPSDataReader.swift:119-157); malformed packets are dropped
- Converts altitude from meters to feet (×3.2808399) and speed from m/s to knots (×1.9438445)
- Updates `GenericLocation` only when X-Plane is the selected source (XGPSDataReader.swift:108)

**GDL90 Devices** (`LocationSource.gdl90`):
- `GDL90Reader` listens on UDP port 4000 for GDL90-formatted packets, plus port 43211 on a best-effort basis (if binding 43211 fails, it keeps listening on 4000 only; if 4000 fails, nothing is started)
- Each port gets its own socket and receive thread; both feed the same `processGDL90Data()`
- Uses the same raw BSD socket approach as `XGPSDataReader` for receiving (never calls `connect()`), to avoid stealing broadcast packets from other GDL90 apps on the same port
- Implements full GDL90 protocol parsing with CRC validation
- Parses Message ID 10 (Ownship Report) for position, pressure altitude, speed, and track
- Parses Message ID 11 (Ownship Geometric Altitude) for geometric altitude
- Altitude fed to `GenericLocation` is geometric (Msg 11) when one arrived within the last `GDL90Reader.geometricAltitudeMaxAge` (3 s), otherwise pressure altitude (Msg 10) as a fallback — see "Altitude datum selection" below
- Broadcasts UDP heartbeat on port 63093 (via `NWConnection`) to advertise availability to GDL90 devices
- Updates `GenericLocation` only when GDL90 is the selected source (GDL90Reader.swift:199)

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
  - Shows selected airport/runway information with distance-to-go (DTG), angle (V/B), and required vertical speed (V/S, ft/min, positive = descent, rounded to 10; `---` when ground speed is unavailable)
  - Displays bearing indicator (arrow) showing direction to destination
  - Switches between GlideSlopeView and PapiView based on `AppSettings.visualization`
  - Double-tap to toggle between visualization modes
  - Favorite airports quick-access section (scrollable horizontal list)
  - Navigation to AirportSelectionView and SettingsView
  - Location staleness warning when GPS signal is lost
  - Pressure altitude caution under the DTG line: orange "⚠ PRESS ALT", shown only when GDL90 is the active source, location isn't stale, and it has fallen back to pressure altitude (nothing is shown when using geometric altitude; internal GPS and X-Plane are always MSL)
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
  - Header size picker (Normal/Large/X-Large) for the DTG and V/B line in ContentView
  - Network information (local IP address for UDP troubleshooting)
  - Aviation database info (last modified date, airport/runway counts)
  - Database update functionality (downloads latest data from remote source)
  - Debug mode toggle
  - Links to debug views (GDL90, Generic Location, Destination Map)
  - "Destination in Google Maps" button: opens a `https://www.google.com/maps/search/?api=1&query=lat,lon` universal link at the selected target coordinates (Google Maps app if installed, otherwise the browser); disabled when no destination is selected

**Debug Views:**

- **GDL90DebugView.swift**: Real-time GDL90 protocol diagnostics
  - Observes `GDL90Reader` only; it never starts or stops the listener (VirtualPAPIApp owns the lifecycle via the selected source). Shows a note when GDL90 is not the selected location source, since no data will arrive then
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
- `HeaderSize`: Normal / Large / X-Large (CaseIterable, Identifiable), exposes a `font` property

**Settings and State:**
- `AppSettings`: Observable settings object with UserDefaults persistence
  - `init(defaults:)` takes the `UserDefaults` store to use (defaults to `.standard`); tests pass an isolated store (see "Unit Tests" below)
  - `locationSource`: Active GPS/simulator source
  - `visualization`: Display mode (glide slope or PAPI)
  - `emaAlpha`: Smoothing factor (0.2 = smooth, 1.0 = instantaneous)
  - `headerSize`: Font size of the DTG and V/B line in ContentView (`HeaderSize` enum: normal = `.body`, large = `.title2`, x-large = `.title`)
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
The XGPS protocol expects packets starting with "XGPS" header followed by comma-separated values. The parser is the pure `nonisolated static func parseXGPS(_ data: Data) -> XGPSFix?` (XGPSDataReader.swift:119-157), called by `processXGPSData(_:)` (XGPSDataReader.swift:159-170), and unit-tested directly ("XGPS Parser Tests" suite):
1. Validates 41+ byte packets with "XGPS" header and at least 6 comma-separated fields
2. Extracts longitude (component 1), latitude (component 2), altitude in meters (component 3), track in degrees (component 4), speed in m/s (component 5); fields are trimmed of whitespace/control characters
3. Rejects the whole packet (returns `nil`, no state update) if any of those fields isn't numeric — never substitutes 0
4. Converts altitude from meters to feet (×3.2808399)
5. Converts speed from m/s to knots (×1.9438445)
6. `processXGPSData` updates both `XGPSDataReader` and `GenericLocation` states (only when X-Plane is selected source)

**Why a raw BSD socket instead of `NWListener`:** `NWListener`'s UDP mode creates a per-sender `NWConnection` by internally `connect()`-ing a socket to the remote address ("established-over-unconnected"). On BSD-derived kernels, a connected socket takes delivery priority over other apps' plain wildcard-bound listening sockets on the same port, so this used to silently steal X-Plane's broadcast packets away from apps like ForeFlight running at the same time. `XGPSDataReader.startListening()` (XGPSDataReader.swift:27-73) instead opens a raw socket with `SO_REUSEADDR`/`SO_REUSEPORT`, binds to `INADDR_ANY:49002`, and only ever calls `recvfrom()` on a dedicated background `Thread` — never `connect()` — so it behaves like a normal passive listener and coexists with other apps.

### GDL90 Protocol Integration
The GDL90 protocol is a standard aviation data link protocol used by many portable GPS and ADS-B receivers. The implementation (GDL90Reader.swift):

**Receiving:** Uses the same raw BSD socket / `recvfrom()` approach as `XGPSDataReader` (GDL90Reader.swift:49-114) for the same reason — avoids stealing UDP broadcast packets from other GDL90-consuming apps on port 4000. The outbound heartbeat broadcast (below) is unaffected and still uses `NWConnection`, since sending isn't subject to this issue.

**Framing and Validation:**
- Messages framed with 0x7E flag bytes
- Byte stuffing: 0x7D escape byte followed by XOR 0x20
- CRC-16-CCITT validation with table-driven lookup (polynomial 0x1021)
- Validates CRC before processing any message

**Message Parsing:**
- Message ID 10 (Ownship Report): Position, pressure altitude, ground speed, track
  - 24-bit signed lat/lon with LSB = 180/2^23 degrees
  - 12-bit altitude with 25 ft resolution, -1000 ft offset (0xFFF = invalid, decoded to nil by `static func GDL90Reader.decodePressureAltitude(_:)`; `GDL90Reader.altitude` is `Double?` and the debug view shows "Invalid")
  - 12-bit velocity with 1 knot resolution (0xFFF = invalid)
  - 8-bit track with LSB = 360/256 = 1.40625 degrees
- Message ID 11 (Ownship Geometric Altitude): 16-bit signed with 5 ft resolution

**Altitude datum selection:**
- The glidepath compares aircraft altitude against MSL runway elevations, but Msg 10 altitude is pressure altitude (29.92 inHg), which can be off by hundreds of feet on non-standard days
- `processGDL90Data` records `geometricAltitudeTime` whenever a Msg 11 arrives; on each Msg 10 the pure `static func GDL90Reader.selectAltitude(pressureAltitude:geometricAltitude:geometricAltitudeTime:now:)` picks geometric altitude if it's at most `geometricAltitudeMaxAge` (3 s, tolerating a couple of dropped 1 Hz messages) old, else pressure altitude
- `pressureAltitude` is optional (nil when Msg 10 reports 0xFFF); if it's nil and there's no fresh geometric altitude, `selectAltitude` returns nil and that Msg 10 does not update `GenericLocation` (nor `usingGeometricAltitude`), so the location goes stale instead of feeding a bogus altitude into the glidepath
- The result is published as `GDL90Reader.usingGeometricAltitude`, which drives the ContentView indicator; unit-tested in the "GDL90 Altitude Selection Tests" suite

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
- Required vertical speed: `verticalSpeedToDestination = (altitude - targetElevation) / (distanceToDestination / groundSpeed × 60)` in ft/min, straight line to the target at current ground speed; `nil` when ground speed is unknown or < 1 kt, or distance is not positive
  - The math lives in the pure `static func GenericLocation.requiredVerticalSpeed(altitude:targetElevation:distance:groundSpeed:)` and display formatting (nearest 10 ft/min, `---` when nil) in `static func ContentView.formatVerticalSpeed(_:)`, so both are unit-tested directly without the timer ("Vertical Speed Tests" suite)
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

### Unit Tests
Tests use Swift Testing. `.serialized` only orders tests *within* a suite; separate suites still run in parallel, so any state shared across suites is a race. In particular, never construct `AppSettings()` in tests: it reads and writes `UserDefaults.standard`, and a setter in one suite (e.g. `locationSource = .xPlane`) can leak into another suite's "default values" assertions. Use `AppSettings(defaults: .isolatedForTesting())` (a fresh, UUID-named suite), or, in `AppSettingsTests`, the per-test `defaults` store that the suite's `init`/`deinit` create and remove.

### Concurrency
- `XGPSDataReader` and `GDL90Reader` use `@MainActor` to ensure all UI updates happen on main thread
- UDP receiving uses raw BSD sockets (`socket`/`bind`/`recvfrom`), each with its own dedicated background `Thread` running a blocking `nonisolated` receive loop (`receiveLoop(fd:)`) — not `NWListener`/`DispatchQueue`, to avoid the socket-priority issue described above
- Both readers' `receiveLoop(fd:)` delegate to the shared `nonisolated func runUDPReceiveLoop(fd:label:onDatagram:)` (UDPReceiveLoop.swift). It skips zero-length datagrams (for UDP, `recvfrom` returning 0 is an empty datagram, not EOF), retries on `EINTR`/`EAGAIN`/`EWOULDBLOCK`, and returns only on a fatal error (e.g. `EBADF` once `stopListening()` has closed the socket; other errors are logged)
- When the loop returns, the reader hops to the main actor and checks whether that thread is still registered (`receiveThread` / `receiveThreads`, compared by identity). `stopListening()` clears those first, so an intentional stop is a no-op; otherwise the exit was unexpected and is surfaced: `XGPSDataReader` calls `stopListening()` (so `isConnected = false`); `GDL90Reader` drops and closes just that socket, and calls `stopListening()` (which sets `isConnected = false` and stops the heartbeat) only once no receive loops remain, since 4000 and 43211 are independent
- `GDL90Reader` still keeps `DispatchQueue(label: "gdl90-udp-queue")` for its outbound heartbeat broadcast (`NWConnection`-based `sendBroadcast()`), which is unrelated to receiving
- Location updates use `Task { @MainActor in ... }` to hop back from the receive thread for thread-safe UI updates
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
