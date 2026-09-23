# Changelog

All notable changes to VirtualPAPI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5] - 2026-09-23

### Added

#### Altitude Integrity
- **GDL90 geometric altitude preferred**: The glidepath now uses Message 11 geometric altitude when one arrived within the last 3 seconds, and falls back to Message 10 pressure altitude (29.92 inHg) only when it has to. Pressure altitude can be hundreds of feet off MSL on a non-standard day
- **Pressure altitude caution**: When GDL90 falls back to pressure altitude, an orange "⚠ PRESS ALT" caution appears under the DTG line and the glide slope diamond turns amber instead of magenta
- **GPS altitude caution**: When internal GPS is the source and its vertical accuracy is worse than 15 m (about 0.45° at 1 NM on a 3° path), an orange "⚠ GPS ALT ±NN ft" caution appears under the DTG line. Guidance keeps working; the caution says the altitude behind it is uncertain

#### Debug Views
- **Internal GPS debug view**: New screen, linked from Settings, that shows everything CoreLocation reports: authorization and Location Services status, tracking/paused state, accepted and rejected fix counts, the last error (with the CLError code named), the last raw fix (including rejected fixes, with the reason), compass heading and the location manager's configuration
- **GDL90 debug view**: Now shows the device heartbeat's "GPS Position" valid flag, the ownship NIC, the track type, the status of the outbound discovery heartbeat and the additional port 43211

#### Developer Tools
- **Continuous integration**: New GitHub Actions workflow builds the app and runs the unit tests on every push and pull request to `main`
- **Unified logging**: All diagnostics now go through `os.Logger` (subsystem `com.mfdutra.VirtualPAPI`) instead of `print`, so they can be read from a user's device with Console.app
- **`gen_sqlite.py` output option**: New `-o/--output` flag, plus a summary of every filter's counts at the end of the run

#### Testing
- **New test suites**: GDL90 wire-format parsing (framing, byte unstuffing, CRC, field decoding), XGPS parsing, GDL90 altitude selection, internal GPS validity and diagnostics, database validation, opening, restoring and row decoding, UDP receiver and listener lifecycle, local IP address lookup, and `AppSettings` migration

### Changed

#### Internal GPS
- **Configured for aircraft use**: CoreLocation now uses the `.airborne` activity type and no longer pauses updates automatically. Before, updates could stop during a long hold short or run-up and never resume, which left the display stale on the take-off roll
- **Runs only when selected**: The internal GPS now stops when X-Plane or GDL90 is the selected source, which saves battery. The location permission prompt now appears only once internal GPS is selected
- **Continuous updates only**: Removed the redundant 2 Hz `requestLocation()` polling timer. Timers piled up on every authorization change and cancelled in-flight requests

#### Airport Selection
- **New search clears the selection**: Typing into the search field while an airport is selected now clears the selection, so the search results replace the runway list

#### Aviation Database
- **Every runway has an elevation and a heading**: `gen_sqlite.py` now skips runway ends with no elevation and runways whose two ends share identical coordinates. It also computes missing headings from the runway end coordinates, so the displaced threshold and aiming point are always applied
- **Data refresh**: Regenerated from the latest OurAirports data (about 8,600 airports and 22,600 runways, down from 11,400 and 29,700 now that unusable runways are excluded)
- **Safer generation**: `gen_sqlite.py` builds into a temporary file and moves it into place only after a successful build. It skips duplicate runway ends and airports with blank coordinates with a warning instead of aborting

#### Privacy
- **Local network permission**: Added the local network usage description that iOS requires for the UDP listeners and the GDL90 discovery broadcast
- **Accurate privacy policy and README**: `PRIVACY.md` and the README now describe the app's actual network use: the GDL90 discovery broadcast on local Wi-Fi, the optional database update from virtualpapi.net, Google Maps from the destination button, and Apple Maps imagery in the Destination Map debug view

### Fixed

#### Guidance Reliability
- **Guidance froze while scrolling**: The 1 Hz guidance update, the staleness check and the GDL90 heartbeat stopped firing while the favorites row was scrolled or a slider was dragged. They now keep running
- **Invalid internal GPS fixes**: Fixes that CoreLocation marks as having an invalid coordinate or altitude are now dropped. Before, an invalid altitude (reported as 0 ft) pegged the diamond at "fly up" and turned the PAPI all red while the location looked fresh. Fixes simulated by software, such as in the Simulator, are still accepted
- **GPS didn't start after granting permission**: On first launch, granting location permission might not start updates until the app was relaunched
- **GDL90 fix without a position**: Ownship reports with NIC 0 (a device with no fix sends lat/lon 0) are no longer treated as a fresh position at 0° N, 0° E, so the location goes stale instead
- **GDL90 track type**: Only a true track now drives the bearing arrow. A magnetic or true heading would have been off by the local variation or wind drift
- **GDL90 invalid altitude**: The Message 10 "no altitude" value (0xFFF) was decoded as 101,375 ft and fed into the glidepath. It's now treated as unavailable
- **Non-finite and out-of-range data**: XGPS and GDL90 values that are NaN, infinite or out of range are now rejected. A NaN could otherwise lock the indicator at full scale until the smoothing was reset

#### Crashes
- **Malformed X-Plane packets**: An XGPS packet with too few fields crashed the app. Packets with missing or non-numeric fields are now dropped
- **Clearing the airport selection**: Clearing the selection could crash when the aiming point change arrived after the runway had already been cleared
- **Settings screen**: Reading the local IP address could crash on a network interface with no assigned address
- **NULL database values**: A NULL airport name or runway identifier in a downloaded database would crash. Such rows are now handled
- **Early X-Plane packet**: A packet processed before the settings were wired up would crash

#### Location Sources
- **Empty UDP datagram ended the feed**: A zero-length datagram or an interrupted system call stopped the X-Plane or GDL90 feed while it still appeared connected
- **Clean listener shutdown**: The UDP receive threads are now woken and stopped before their sockets close. Before, a stopped thread could be left waiting on a socket descriptor that the system later reused
- **GDL90 debug view**: Opening the view no longer starts a second listener, and closing it no longer stops the GDL90 feed

#### Aviation Database
- **Remote updates are validated**: A downloaded database is now checked (SQLite format, integrity, schema and minimum airport and runway counts) before it's installed, and the previous database is kept as a backup. Before, a captive-portal page or truncated download would replace the live database for good
- **Stale "up-to-date" after an app update**: When the bundled database replaces the downloaded one, the stored download version is cleared, so the next update check really downloads
- **Corrupt or missing database recovery**: The database is now opened read-only, a broken file is replaced by the bundled copy at launch, and any remaining failure is shown in Settings. Before, a failed copy could leave an empty database that was never replaced
- **Thread safety**: All database access is serialized, so queries during a remote update wait instead of hitting a closed connection

#### Settings
- **Favorites**: `AirportSelection` is now the only owner of saved favorites. A second, unused copy in `AppSettings` could have overwritten them

### Technical Details

#### Removed
- Unused private `_LocationEssentials` import (fragile across SDKs and flagged by App Review) and unused SwiftData imports
- Dead `AppSettings.useXPlane` property. The legacy setting is still migrated on first launch

#### Build
- **Warning-free**: The app and test targets build with no warnings. Code that uses iOS 27 SDK-only API is guarded so CI can still build with Xcode 26
- **SQLite binding**: Text parameters are now bound with `SQLITE_TRANSIENT`, so SQLite copies them instead of relying on a temporary buffer

---

## [1.4] - 2026-09-15

### Added

#### Navigation Display
- **Required vertical speed (V/S)**: New field on the main screen showing the ft/min needed to fly a straight line from the current position and altitude to the target at the current ground speed
- **Descent convention**: Positive values indicate a descent, rounded to the nearest 10 ft/min
- **Graceful fallback**: Displays `---` when ground speed is unavailable or below 1 kt, or when distance is not positive
- **Configurable header size**: New "Header size" picker (Normal / Large / X-Large) under Visualization in Settings, applied to the DTG and V/B line in ContentView and persisted in `AppSettings`

#### Location Sources
- **Additional GDL90 port**: `GDL90Reader` now also listens on UDP port 43211 (used by the iLevil 3 AW) in addition to port 4000
- **Best-effort binding**: If port 43211 cannot be bound, the reader keeps listening on port 4000 only; each port gets its own socket and receive thread feeding the same parser

#### Settings
- **Destination in Google Maps**: New button in Settings opens a Google Maps universal link pinned at the selected target coordinates (Google Maps app when installed, otherwise the browser); disabled when no destination is selected

#### Developer Tools
- **Runway check script**: New `scripts/rwy_check.py` reads `aviation.db`, projects displaced threshold coordinates with the haversine formula, and outputs a KML file with styled points and lines for each threshold
- **Push checklist**: New `PUSH_CHECKLIST.md` documenting the release/publish steps

#### Testing
- **Vertical Speed test suite**: Unit tests covering the required vertical speed calculation and its display formatting

### Changed

#### UDP Receive Architecture
- **Raw BSD sockets**: `XGPSDataReader` and `GDL90Reader` now receive with `socket`/`bind`/`recvfrom` on a dedicated background thread instead of `NWListener`
- **No longer steals broadcasts**: `NWListener`'s UDP mode `connect()`s its underlying socket to each sender, which on BSD-derived kernels takes delivery priority over other apps' plain listening sockets on the same port — this silently stole X-Plane XGPS packets (port 49002) and GDL90 packets (port 4000) from other apps such as ForeFlight
- **Socket options**: Sockets bind to `INADDR_ANY` with `SO_REUSEADDR`/`SO_REUSEPORT` and never call `connect()`, behaving as normal passive listeners
- **Heartbeat unchanged**: `GDL90Reader`'s outbound heartbeat broadcast still uses `NWConnection`, since sending is unaffected

#### User Interface
- **"ANG" renamed to "V/B"**: The angle field on the main screen is now labeled V/B (vertical bearing), matching Boeing terminology

#### Aviation Database
- **Closed runways excluded**: `gen_sqlite.py` now skips runways flagged as closed, so they no longer appear in selection
- **Multiple data refreshes**: Several `aviation.db` regenerations with the latest airport and runway data from OurAirports.com

### Technical Details

#### Required Vertical Speed
- **Formula**: `(altitude - targetElevation) / (distanceToDestination / groundSpeed × 60)` in ft/min
- **Pure functions**: Math lives in `GenericLocation.requiredVerticalSpeed(altitude:targetElevation:distance:groundSpeed:)` and formatting in `ContentView.formatVerticalSpeed(_:)`, so both are unit-tested directly without the update timer
- **Nil cases**: Returns `nil` when ground speed is unknown or < 1 kt, or distance is not positive

#### Google Maps Link
- **URL format**: `https://www.google.com/maps/search/?api=1&query=<lat>,<lon>` at the selected target coordinates
- **Opened via**: SwiftUI's `@Environment(\.openURL)`

---

## [1.3] - 2025-12-07

### Added

#### Glide Slope Smoothing
- **Configurable responsiveness**: Exponential Moving Average (EMA) filtering for glide slope indicator
- **Adjustable alpha values**: Smooth (0.2), Medium (0.5), Fast (0.8), or Instantaneous (1.0)
- **Settings integration**: Responsiveness slider in Settings view
- **Debug mode visualization**: Display both smoothed and raw glide slope indicators simultaneously
- **Persistent preferences**: Smoothing setting saved to UserDefaults

#### Navigation Enhancements
- **GPS-provided ground speed**: Direct parsing from XGPS and GDL90 protocols (no longer calculated)
- **GPS-provided track**: Direct parsing from XGPS and GDL90 protocols (no longer calculated)
- **Heading calculation**: New `heading(from:to:)` method for bearing calculations
- **Relative bearing**: Calculate where destination is relative to current track
- **Bearing to destination**: Absolute bearing from current position to destination

#### Visualization & Debugging
- **Satellite map view**: DestinationMapView displays selected runway on satellite imagery
- **Maximum zoom**: 500-meter distance view centered on aiming point
- **Pin marker**: Visual indicator at calculated aiming point (includes displaced threshold)
- **Debug access**: Map view accessible from Settings > Debug section
- **Enhanced debug displays**: Updated GenericLocationDebugView with speed/track information

#### Developer Tools
- **RNAV approach simulator**: Python script (`simulate_flight.py`) for integration testing
- **Waypoint-based flight**: Simulates aircraft following GPS waypoints
- **UDP message generation**: Sends X-Plane-compatible XGPS packets every second
- **Test data included**: Sample RNAV approach profiles for KHWD runway 28L
- **No simulator required**: Enables testing without running full flight simulator

#### Testing
- **33 comprehensive unit tests**: Full coverage of new features since v1.2
- **GenericLocation tests**: Heading calculations, speed/track updates, EMA smoothing (10 tests)
- **XGPSDataReader tests**: Speed and track parsing with unit conversions (4 tests)
- **AppSettings tests**: EMA alpha persistence and smoothing levels (4 tests)
- **DatabaseManager tests**: Airport search and table row counts (7 tests)
- **String extension tests**: Left padding utility for base32 decoding (6 tests)
- **Thread safety**: Serialized test execution to prevent SQLite concurrency issues

### Changed

#### Location Data Processing
- **XGPS protocol parsing**: Now extracts track (component 4) and speed (component 5) from packets
- **GDL90 protocol parsing**: Parses Message ID 10 for horizontal velocity and track
- **Unit conversions**: Speed converted from m/s to knots (×1.9438445)
- **Track encoding**: GDL90 track decoded with 1.40625° resolution (360/256)
- **Invalid speed handling**: GDL90 velocity 0xFFF indicates invalid/unavailable speed
- **Location update signature**: Added optional `speed` and `track` parameters to `updateLocation()`

#### User Interface
- **Responsiveness control**: New slider in Settings for EMA alpha adjustment
- **Visual feedback**: Smooth/Medium/Fast/Instantaneous labels for smoothing levels
- **Debug mode enhancement**: Dual glide slope indicators when debug info enabled
- **Settings organization**: Debug views grouped in dedicated section

#### Code Organization
- **Reusable navigation functions**: Extracted `heading()` method for bearing calculations
- **Bearing updates**: New `updateBearingToDestination()` method
- **Relative bearing calculation**: Normalized to ±180° range for intuitive display
- **Smooth glide slope tracking**: Separate `smoothedAngleDeviation` and `smoothedGsOffset` properties

### Technical Details

#### EMA Smoothing Algorithm
- **Formula**: `EMA_new = alpha × current + (1 - alpha) × EMA_previous`
- **Alpha range**: 0.2 (highly smoothed) to 1.0 (no smoothing/instantaneous)
- **Application**: Applied to angle deviation before display offset calculation
- **Initialization**: First value used directly, subsequent values smoothed
- **Debug output**: Console logging of both raw and smoothed deviation values

#### Protocol Parsing Details

**XGPS Format:**
- Track: Component 4 (degrees, 0-360)
- Speed: Component 5 (m/s, converted to knots)
- Conversion factor: 1.9438445 (m/s to knots)

**GDL90 Format:**
- Track: Byte 17, LSB = 1.40625° (360/256)
- Speed: Bytes 14-15 (12-bit), 1 knot resolution
- Invalid speed: 0xFFF indicates no valid data
- Message structure: Ownship Report (Message ID 10)

#### Navigation Calculations
- **Heading method**: Uses forward azimuth formula on WGS84 ellipsoid
- **Range**: Returns 0-360° where 0° is North, 90° is East
- **Relative bearing**: `destination_bearing - current_track`, normalized to ±180°
- **Positive values**: Turn right to reach destination
- **Negative values**: Turn left to reach destination

#### Test Coverage
- **Serialization**: DatabaseManager and GenericLocation tests run serially to avoid SQLite threading issues
- **MainActor isolation**: Async tests properly annotated for SwiftUI compatibility
- **Mock data**: Realistic test scenarios with actual airport/runway coordinates
- **Tolerance ranges**: Appropriate epsilon values for floating-point comparisons

### Aviation Database Updates
- Multiple database updates with latest airport and runway data from OurAirports.com
- Enhanced search functionality tested with comprehensive test suite

---

## [1.2] - 2025-11-24

### Added

#### Remote Database Management
- **Remote database updates**: Automatic aviation database downloads from https://virtualpapi.net
- **TOTP authentication**: RFC 6238 compliant time-based one-time password security for update endpoint
- **ETag caching**: HTTP ETag support to avoid unnecessary downloads (304 Not Modified handling)
- **gzip compression**: Compressed database transfers for reduced bandwidth
- **Manual update trigger**: "Check for Updates" button in Settings with real-time status feedback
- **Database statistics**: Display airport and runway counts in Aviation Database section
- **Modification date display**: Shows last database update timestamp in Settings

#### Motion Tracking & Navigation
- **Ground speed calculation**: Real-time ground speed in knots based on position changes
- **Track calculation**: Current ground track in degrees
- **Bearing calculations**: Absolute and relative bearings to destination
- **Navigation debug view**: Comprehensive GenericLocationDebugView for monitoring location and motion data
- **Color-coded display**: Navigation data formatted with proper units and visual indicators

#### Airport Search Enhancements
- **Extended search fields**: Now searches across ident, iata_code, local_code, gps_code, and icao_code
- **Database indexes**: Performance optimization for faster search queries
- **Flexible data import**: gen_sqlite.py accepts CSV file paths as command-line arguments

### Changed

#### Database Architecture
- **Singleton pattern**: DatabaseManager converted to shared instance to prevent duplicate initialization
- **Writable storage**: Database moved from app bundle to Documents directory for remote updates
- **Automatic version checking**: Compares bundle and Documents database dates, updates if bundle is newer
- **First-launch copy**: aviation.db automatically copied to Documents on initial app launch

#### Code Organization
- **Reusable heading function**: Extracted heading(from:to:) for navigation calculations
- **Centralized motion updates**: New updateMotionInfo() method for ground speed and track
- **Bearing updates**: updateBearingToDestination() calculates relative navigation angles

### Security

#### TOTP Implementation
- **Base32 decoding**: Custom implementation for TOTP secret key processing
- **HMAC-SHA1**: Cryptographic authentication code generation
- **30-second time steps**: Standard TOTP time window
- **Secrets.swift**: TOTP secret stored in gitignored file (not in version control)
- **URL obfuscation**: Remote endpoint path protection (removed in TOTP update)

### Technical Details

#### Database Management
- Database path: `~/Documents/aviation.db`
- Version checking: Modification date comparison
- Update flow: Close DB → Download → Write → Reopen
- ETag storage: UserDefaults persistent cache
- Download timestamp tracking

#### Motion Calculations
- Ground speed: Position delta / time delta (converted to knots)
- Track: Bearing from previous position to current position
- Update frequency: Calculated on each location update
- Minimum delta: Prevents erratic calculations from GPS jitter

#### TOTP Authentication
- Algorithm: HMAC-SHA1
- Digits: 6
- Period: 30 seconds
- Format: `?totp=XXXXXX` query parameter

### Developer Notes

#### Secrets Configuration
Create `VirtualPAPI/Secrets.swift` (gitignored):
```swift
import Foundation
enum Secrets {
    static let totpSecret = "YOUR_TOTP_SECRET_KEY"
}
```

#### Database Updates
All views using DatabaseManager should now reference:
```swift
DatabaseManager.shared.getAirport(ident: "KJFK")
DatabaseManager.shared.searchAirports(query: "JFK")
DatabaseManager.shared.getRunways(forAirport: "KJFK")
DatabaseManager.shared.getTableRowCounts()
```

---

## [1.1] - 2025-11-21

### Added

#### PAPI Visualization Mode
- **Dual visualization system**: New PAPI (Precision Approach Path Indicator) display alongside existing glide slope view
- **Four-light PAPI display**: Authentic red/white light simulation with smooth color transitions
- **Visualization selector**: Settings picker to choose between "Glide Slope" and "PAPI" modes
- **Quick toggle**: Double-tap gesture on visualization area to instantly switch between modes
- **PAPI calculations**: Real-time angle deviation and position-based color calculations
  - 2 red / 2 white = on glide path
  - More white = above glide path
  - More red = below glide path

#### GDL90 Protocol Support
- **GDL90 location source**: Third option for receiving GPS data via GDL90 protocol
- **UDP broadcast discovery**: App announces presence on port 63093 every 5 seconds
- **GDL90 message parser**: Decodes OWNSHIP and GPS TIME messages
- **Debug view**: Real-time GDL90 protocol inspection and message monitoring
- **Multi-source architecture**: Unified LocationSource enum replacing boolean toggle
  - Internal GPS (device location)
  - X-Plane (XGPS protocol)
  - GDL90 (aviation standard)

#### Favorite Airports
- **Star/unstar airports**: Quick access to frequently used destinations
- **Persistent storage**: Favorites saved to UserDefaults across app launches
- **Quick-select cards**: Favorites displayed when no airport is active
- **Inline favoriting**: Star icon in search results and main screen

#### User Experience
- **Screen timeout prevention**: Display stays on during active navigation
- **Location staleness indicator**: "INVALID" warning when GPS signal is lost (5-second timeout)
- **Improved navigation**: Emoji icons on navigation links for better visual clarity
- **Settings organization**: Visualization and location source pickers in dedicated sections

### Changed

#### Architecture Improvements
- **Centralized listener management**: All location source listeners (GPS, X-Plane, GDL90) now managed in VirtualPAPIApp
- **Unified location updates**: New `GenericLocation.updateLocation()` method with automatic timestamp tracking
- **View separation**: Extracted glide slope indicator into standalone GlideSlopeView component
- **Enhanced state management**: Better lifecycle handling for background/foreground transitions

#### Location Handling
- **LocationSource enum**: Replaced `useXPlane` boolean with multi-option enum
- **Automatic staleness detection**: 5-second timer monitors location freshness
- **Timestamp tracking**: All location updates now include precise timing information

### Testing

#### New Test Coverage
- **PAPI tests**: Position calculation and color array validation
- **Visualization tests**: Settings persistence and enum behavior
- **Updated XGPS tests**: Reflect new LocationSource architecture
- **45 passing unit tests**: Comprehensive coverage of core functionality

#### Test Infrastructure
- **locationSource migration**: All tests updated from useXPlane to locationSource
- **Removed flaky tests**: Timer-dependent tests excluded for reliability
- **Test cleanup**: UserDefaults properly reset between test runs

### Technical Details

#### PAPI Algorithm
- Position calculated as `(angleDeviation + 0.7) / 1.4`
- Color transitions use 4-step gradient based on position
- Colors ordered from left to right: `[0], [1], [2], [3]`
- Smooth animations with 1-second linear duration

#### GDL90 Implementation
- Listens on UDP port 4000
- Broadcasts heartbeat on port 63093
- Parses message types: 0x0A (OWNSHIP), 0x65 (GPS TIME)
- Message format validation and CRC checking

#### Location Staleness
- Updates monitored every 5 seconds
- Stale indicator appears when no updates received
- Affects both Glide Slope and PAPI visualizations
- Automatic recovery when signal returns

### Developer Notes

#### Migration Guide
If you have custom code referencing `useXPlane`:
```swift
// Old
settings.useXPlane = true

// New
settings.locationSource = .xPlane
```

#### New Environment Objects
Views now have access to:
- `AppSettings.visualization` (VisualizationType)
- `AppSettings.locationSource` (LocationSource)
- `GenericLocation.papiPosition` (Double, 0.0-1.0)
- `GenericLocation.papiColors` ([Double], 4 elements)
- `GenericLocation.angleDeviation` (Double, degrees)

---

## [1.0.2] - Previous Release

See git history for changes prior to v1.0.2.
