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
# Run UI tests
xcodebuild test -scheme VirtualPAPI -only-testing:VirtualPAPIUITests -destination 'platform=iOS Simulator,name=iPhone 17'

# Run unit tests natively on an Apple silicon Mac (no simulator), as a "Designed for iPad" app
xcodebuild test -scheme VirtualPAPI -only-testing:VirtualPAPITests -destination 'platform=macOS,arch=arm64,variant=Designed for iPad'
```

When running on the Mac, the `Executed 0 tests` line only counts XCTest tests; Swift Testing reports its results on the `Test run with N tests ... passed` line. The `[AXLoading] ... ScreenTimeUI` errors, `#Spi, CLInternalGetPrecisionPermission failed` lines (logged when tests construct a `HighFrequencyLocationTracker`, whose `CLLocationManager` has no location permission on the Mac) and `appintentsmetadataprocessor` warnings are harmless macOS noise. This is much faster than the simulator (about 20 s vs several minutes), so prefer it for unit tests.

### Continuous Integration
`.github/workflows/swift.yml` runs on pushes and PRs to `main` on a `macos-26` runner, because the iOS 26 deployment target needs the Xcode 26 SDK. It's an Xcode project, not a Swift package, so it uses `xcodebuild` and not `swift build`. It writes a placeholder `VirtualPAPI/Secrets.swift`, since the real one is gitignored and only the remote database update uses it. It then picks the first available iPhone simulator, runs `build-for-testing` with `CODE_SIGNING_ALLOWED=NO`, and runs `test-without-building -only-testing:VirtualPAPITests`. UI tests aren't run in CI.

### Database Generation
The `scripts/` directory contains aviation data from ourairports.com:
```bash
# Regenerate the SQLite database from CSV files (default output: ./aviation.db)
cd scripts
./gen_sqlite.py path/to/airports.csv path/to/runways.csv

# Write somewhere else, e.g. straight over the bundled copy
./gen_sqlite.py path/to/airports.csv path/to/runways.csv -o ../VirtualPAPI/aviation.db
```

Both CSV paths are required positional arguments; `-o/--output` chooses the destination (default `aviation.db` in the current directory). The script processes:
- `airports.csv`: Airport locations and elevations
- `runways.csv`: Runway coordinates, headings, and displaced thresholds

The database is built into a temporary file next to the destination and moved into place with `os.replace()` only after a successful build, so an aborted or failing run can never leave a partial/corrupt `aviation.db` behind. A summary of every filter's counts is printed at the end.

Filtering rules applied by the script:
- Airports with a blank `latitude_deg`/`longitude_deg` are skipped: the app reads coordinates as non-optional doubles, so such an airport would silently sit at 0,0 (Null Island). Runways belonging to a skipped airport are removed too. None exist in the current data
- Runways that are closed, have missing end coordinates or identifiers, or whose two ends share identical coordinates are skipped
- Two runway ends with the same identifier at the same airport collide on the `PRIMARY KEY (airport_ident, ident)`: the first is kept and the rest are skipped with a warning and counted, rather than aborting the build. None exist in the current data
- Each runway end is stored as its own row; ends with no elevation data are skipped, so every runway in the database has an elevation
- Airports left with no runways after this filtering are removed
- Missing runway end headings are backfilled: when `le_heading_degT`/`he_heading_degT` is blank, the script stores the true initial great-circle bearing from that end's coordinates to the opposite end's (headings present in the CSV are kept as is). Since runways with identical end coordinates are skipped, every runway in the database has a heading, so `AirportSelection.calculateAimingPoint()` can always apply the displaced threshold and aiming point

**Database Management:**
- `DatabaseManager` (singleton) handles SQLite operations
- Database copied from bundle to Documents directory on first launch
- Supports remote database updates via `downloadRemoteDatabase()` method (TOTP-authenticated, ETag-cached, `@concurrent` so the network wait and file work run off the main thread). The update is transactional:
  1. Downloads to a temporary file (`URLSession.download(for:)`), rejecting anything over `maxDatabaseSize` (50 MB; bundled DB is ~3.5 MB) by Content-Length and by actual file size
  2. Validates the staged file (`Documents/aviation.db.download`) with `static func validateDatabase(at:)`: SQLite header magic, read-only open, `PRAGMA integrity_check` == "ok", `airports`/`runways` tables with the columns the app queries, and counts >= `minAirportCount` (5,000) / `minRunwayCount` (15,000) (bundled DB has ~11,400 / ~29,700)
  3. Only then calls `replaceDatabase(with:backupName:)`, which closes the live handle and swaps the staged file in with `FileManager.replaceItemAt`, keeping the previous DB as `aviation.db.bak`; if reopening fails, the backup is restored
  4. Stores the ETag and `last_database_download` only after a successful swap, so a failed update is retried next time
  - Whenever the bundled database is copied over the Documents one (first launch, or the bundle file is newer, which after a fresh git checkout means every app update), `copyDatabaseToDocuments` clears `aviation_db_etag` and `last_database_download`. Otherwise the next check would send the old download's ETag in `If-None-Match`, get a 304 and report "up-to-date" while the app is actually on the bundled data
  - Failures surface as `DatabaseError` (a `LocalizedError`: `tooLarge`, `invalidDatabase`, `installFailed`, plus HTTP/URL errors), shown in SettingsView
  - Validation is unit-tested ("Database Validation Tests") against the bundled DB, HTML, empty, truncated, empty-tables and wrong-schema files
- Thread-safe: `DatabaseManager` is `nonisolated final class ... @unchecked Sendable` (opted out of the default `MainActor` isolation) and serializes every access to the SQLite handle on a private serial `DispatchQueue`. Public methods (`getAirport`, `searchAirports`, `getRunways`, `getTableRowCounts`, `replaceDatabase(with:backupName:)`) wrap `queue.sync`; the private `fetch*`/`openDatabase`/`closeDatabase` helpers assume they're already on the queue (`dispatchPrecondition`) and must never call `queue.sync` themselves (deadlock)
- `replaceDatabase(with:backupName:)` does close → swap file → reopen (→ roll back to the backup if the reopen or the row-count check fails) as one queue block, so concurrent queries wait instead of hitting a closed/nil handle; closing uses `sqlite3_close_v2` (never fails with `SQLITE_BUSY`/leaks the connection). The staging file must sit in Documents next to the live DB so the swap is an atomic same-volume rename
- The live database is opened read-only via `static func openReadOnly(atPath:)` (`sqlite3_open_v2` with `SQLITE_OPEN_READONLY`; the app never writes to it), which also compiles a query against `airports` so a missing, empty or non-SQLite file fails at open time. Never use `sqlite3_open` (READWRITE | CREATE) here: if the bundle copy failed it would silently create an empty `aviation.db` that, being newer than the bundle, would never be replaced. At launch, `init` opens through `static func openOrRestore(atPath:bundlePath:defaults:)`: if the open fails, it copies the bundled database over the Documents one (via `static func copyDatabase(from:to:defaults:)`, so the ETag and `last_database_download` are cleared too) and retries once; `replaceDatabase` opens without the restore, since it has its own backup rollback. Both helpers take their paths and `UserDefaults` store as parameters so tests drive them against temp files and `.isolatedForTesting()`. `ensureDatabaseIsUpToDate()` only compares modification dates, so without this a corrupt Documents file newer than the bundle would stay broken until a remote update, which needs a network connection. A failure that remains is kept as `openFailure` (`DatabaseError.openFailed`), shown in SettingsView's Aviation Database section ("Airports: Unavailable" plus the reason); a successful reopen (e.g. after an update) clears it. Covered by the "Database Open Tests" suite (missing/empty/non-SQLite files, and restore: valid DB kept, corrupt or missing DB restored with metadata cleared, failed restore reported)
- Provides query methods: `getAirport(ident:)`, `searchAirports()`, `getRunways(airportId:)`
- Row decoding is shared by the query methods: `static func airport(from:)` and `static func runway(from:airportIdent:)` read the current row, and every text column goes through `static func columnText(_:_:)` (`sqlite3_column_text` returns nil for a NULL column and `String(cString:)` would trap on it). The schema permits NULL in those columns and validation doesn't check for it, so a remote update could introduce one: a NULL `name` becomes `""`, while a row with a NULL `ident` is unusable and is skipped (`getAirport` returns nil; `searchAirports`/`getRunways` drop it from the list). Covered by the "Database Row Decoding Tests" suite, which drives the decoders directly against temp databases, since the query methods can only read the app's own database in Documents
- Returns table counts for diagnostics

## Architecture

### State Management Pattern
The app uses SwiftUI's `@StateObject` and `@EnvironmentObject` pattern for global state:

1. **VirtualPAPIApp.swift** (app entry point) creates six core state objects:
   - `AppSettings`: User preferences (location source, visualization type, debug info, smoothing)
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
- `HighFrequencyLocationTracker` uses CoreLocation continuous updates (`startUpdatingLocation()` with `kCLLocationAccuracyBest` and `kCLDistanceFilterNone`, ~1 Hz); no timer or `requestLocation()` polling, so repeated `startTracking()` calls (e.g. on authorization changes) are harmless
- Configured for aircraft use: `activityType = .airborne` (no ground-vehicle filtering) and `pausesLocationUpdatesAutomatically = false`. With automatic pausing on (the default), CoreLocation stops delivering fixes once it decides the device is stationary (a long hold short or run-up) and doesn't resume on its own, so the display would go stale on the take-off roll. Covered by the "Internal GPS Diagnostics Tests" suite
- Instantiated in VirtualPAPIApp, but only tracks while internal GPS is the selected source: `startListenerForSource(.internalGPS)` calls `startTracking()` and `stopListenerForSource(.internalGPS)` calls `stopTracking()`, so best-accuracy GPS doesn't drain the battery while X-Plane or GDL90 is selected. Consequently, the location permission prompt appears only once internal GPS is selected
- Authorization handled via `locationManagerDidChangeAuthorization(_:)` (reads `manager.authorizationStatus`; the deprecated `didChangeAuthorization:` callback is not used). On first launch `startTracking()` only requests permission and records intent (`isTracking = true`); the callback starts updates once authorized. `startTracking()` is idempotent (private `isUpdatingLocation` guard), so the callback re-invoking it never starts updates twice. Denied/restricted stops updates but keeps `isTracking`, so tracking resumes if permission is later granted in Settings
- Updates `GenericLocation` with position, speed, and track data
- CoreLocation's validity convention (negative = invalid) is applied to all four fields, not just speed/course: a fix with a negative `horizontalAccuracy` (invalid coordinate) or negative `verticalAccuracy` (invalid altitude, typically reported as `altitude == 0`, which would peg the glidepath at "fly up") is dropped whole in `didUpdateLocations` before anything is published, so the previous fix stands and the location goes stale on its own
- Exception: fixes with `sourceInformation.isSimulatedBySoftware == true` skip both accuracy checks (`rejectionReason(horizontalAccuracy:verticalAccuracy:isSimulatedBySoftware:)` returns nil), so internal GPS works in the Simulator. Such fixes carry `altitude == 0`, so vertical guidance there reflects a 0 ft altitude (typically "fly up"); lateral data (DTG, bearing) is real
- `verticalAccuracy` (metres, 1 sigma) is published alongside the existing horizontal `accuracy`; `verticalAccuracyIsPoor` is true above `HighFrequencyLocationTracker.poorVerticalAccuracy` (15 m, about 0.45° at 1 NM on a 3° path, inside the display's 0.7° full-scale deflection) and drives the ContentView caution
- Diagnostics for InternalLocationDebugView are published too: `lastRawLocation` (every fix CoreLocation delivers, set *before* the validity guard, so dropped fixes are visible), `lastRejectionReason` (from the pure `static func rejectionReason(horizontalAccuracy:verticalAccuracy:)`, which the guard itself uses), `acceptedFixCount`/`rejectedFixCount`, `lastError`/`lastErrorTime` (from `didFailWithError`, named via `static func describe(_:)` since `localizedDescription` is only "kCLErrorDomain error N"), `updatesPaused` (pause/resume callbacks), `accuracyAuthorization`, `locationServicesEnabled` (queried off the main thread, since `CLLocationManager.locationServicesEnabled()` can block), and read-only manager configuration (`desiredAccuracy`, `distanceFilter`, `activityType`, `pausesLocationUpdatesAutomatically`, `headingFilter`)
- Compass heading (`heading: CLHeading?`) is diagnostics only (guidance uses GPS track): `startHeadingUpdates()`/`stopHeadingUpdates()` are called by InternalLocationDebugView's `onAppear`/`onDisappear`, so heading runs only while that screen is shown. This is separate from the location-source lifecycle, which views must not touch
- In the Simulator every simulated fix (`simctl location set`, and built-in scenarios such as "Freeway Drive") arrives with `verticalAccuracy = -1`, `altitude = 0` and `isSimulatedBySoftware == true` (verified), because `simctl` has no altitude parameter. They are accepted through the simulated-fix exception above; InternalLocationDebugView marks them "Accepted" with a "Simulated fix: accuracy checks skipped" note
- Only updates GenericLocation when internal GPS is the active source (a fix already in flight when the source changes is ignored)

**X-Plane Simulator** (`LocationSource.xPlane`):
- `XGPSDataReader` listens on UDP port 49002 for XGPS format packets
- Uses a raw BSD socket (not `NWListener`) that never calls `connect()`, so it can't steal broadcast packets from other apps listening on the same port (e.g. ForeFlight) — see "Concurrency" below
- Parses lat/lon/alt/speed/track from comma-separated ASCII data via the pure `nonisolated static func XGPSDataReader.parseXGPS(_:)` (XGPSDataReader.swift:94-122); malformed packets are dropped
- Converts altitude from meters to feet (×3.2808399) and speed from m/s to knots (×1.9438445)
- Updates `GenericLocation` only when X-Plane is the selected source (XGPSDataReader.swift:69)

**GDL90 Devices** (`LocationSource.gdl90`):
- `GDL90Reader` listens on UDP port 4000 for GDL90-formatted packets, plus port 43211 on a best-effort basis (if binding 43211 fails, it keeps listening on 4000 only; if 4000 fails, nothing is started)
- Each port gets its own socket and receive thread; both feed the same `processGDL90Data()`
- Uses the same raw BSD socket approach as `XGPSDataReader` for receiving (never calls `connect()`), to avoid stealing broadcast packets from other GDL90 apps on the same port
- Implements full GDL90 protocol parsing with CRC validation
- Parses Message ID 10 (Ownship Report) for position, pressure altitude, speed, and track
- Parses Message ID 11 (Ownship Geometric Altitude) for geometric altitude
- Altitude fed to `GenericLocation` is geometric (Msg 11) when one arrived within the last `GDL90Reader.geometricAltitudeMaxAge` (3 s), otherwise pressure altitude (Msg 10) as a fallback — see "Altitude datum selection" below
- Broadcasts UDP heartbeat on port 63093 (via `NWConnection`) to advertise availability to GDL90 devices
- Updates `GenericLocation` only when GDL90 is the selected source (GDL90Reader.swift:200)

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
  - In that same state the glide slope diamond turns amber (`ContentView.uncertainAltitudeColor`, orange) instead of magenta, so the caution is on the indicator itself, not only in the caption. Both are driven by the pure `static func ContentView.isUsingPressureAltitude(locationSource:locationIsStale:usingGeometricAltitude:)`; the diamond color comes from `static func diamondColor(locationIsStale:usingPressureAltitude:)` (stale yellow wins, then amber, else magenta). The DTG/V/B/V/S header numbers keep the normal magenta/stale colors. Covered by the "Pressure Altitude Caution Tests" suite
  - Uncertain GPS altitude caution under the DTG line: orange "⚠ GPS ALT ±NN ft" (`static func ContentView.formatVerticalAccuracy(_:)`, metres converted to feet and rounded to 10), shown only when internal GPS is the active source, location isn't stale, and `HighFrequencyLocationTracker.verticalAccuracyIsPoor`. Guidance keeps working; the pilot is just told the altitude behind it is uncertain
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
  - Typing into the search field while an airport is selected clears the selection (`airportSelection.clear()`, runway list emptied) on the first character, so the search results replace the runway list. Only non-empty text triggers this: `selectAirport` resetting `searchText` to `""` doesn't clear the airport it just set, and `@SceneStorage` restoring the text doesn't fire `.onChange`
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
  - Links to debug views (GDL90, Internal GPS, Generic Location, Destination Map)
  - "Destination in Google Maps" button: opens a `https://www.google.com/maps/search/?api=1&query=lat,lon` universal link at the selected target coordinates (Google Maps app if installed, otherwise the browser); disabled when no destination is selected

**Debug Views:**

- **GDL90DebugView.swift**: Real-time GDL90 protocol diagnostics
  - Observes `GDL90Reader` only; it never starts or stops the listener (VirtualPAPIApp owns the lifecycle via the selected source). Shows a note when GDL90 is not the selected location source, since no data will arrive then
  - Shows the device heartbeat's "GPS Position" (valid / not valid / no heartbeat), the ownship NIC (red "no valid position" below `GDL90Reader.minimumNIC`) and the track type (orange unless true track)
- **InternalLocationDebugView.swift**: Everything CoreLocation reports for the internal GPS
  - Status (authorization, accuracy authorization, Location Services, tracking/updating/paused, accepted/rejected fix counts, last error), the last raw fix with whether the guidance accepted or rejected it and why (coordinate, horizontal accuracy, MSL and ellipsoidal altitude, vertical accuracy, speed and speed accuracy, course and course accuracy, floor, simulated-by-software / produced-by-accessory), compass heading (magnetic, true, accuracy, raw magnetic field) and the manager configuration
  - Negative (invalid) CoreLocation values are shown as "invalid (N)" in red; vertical accuracy above `poorVerticalAccuracy` is orange. A `TimelineView` refreshes the age rows every second
  - Formatting is in pure static helpers (`formatAccuracy(_:unit:)`, `describe(_:)` for authorization status and activity type, `describeDesiredAccuracy(_:)`)
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
  - `init` migrates the legacy `useXPlane` boolean: when no `locationSource` is stored but `useXPlane` is `true`, the source becomes `.xPlane`. The old key is only read, never written, and there is no `useXPlane` property
  - Does not own favorites: `AirportSelection` is the sole owner of the `"favoriteAirports"` UserDefaults key

- `AirportSelection`: Observable selection state
  - Selected airport and runway references
  - Descent angle and aiming point configuration
  - Target coordinates (calculated from runway + displaced threshold + aiming point)
  - Favorite airports management (`favoriteAirports: Set<String>`, `isFavorite`, `toggleFavorite`) with UserDefaults persistence under the `"favoriteAirports"` key — the single store for favorites

## Key Implementation Details

### X-Plane UDP Integration
The XGPS protocol expects packets starting with "XGPS" header followed by comma-separated values. The parser is the pure `nonisolated static func parseXGPS(_ data: Data) -> XGPSFix?` (XGPSDataReader.swift:94-122), called by `processXGPSData(_:)` (XGPSDataReader.swift:124-135), and unit-tested directly ("XGPS Parser Tests" suite):
1. Validates 41+ byte packets with "XGPS" header and at least 6 comma-separated fields
2. Extracts longitude (component 1), latitude (component 2), altitude in meters (component 3), track in degrees (component 4), speed in m/s (component 5); fields are trimmed of whitespace/control characters
3. Rejects the whole packet (returns `nil`, no state update) if any of those fields isn't numeric — never substitutes 0 — or is non-finite (`Double(String)` accepts "nan"/"inf"/hex floats)
4. Converts altitude from meters to feet (×3.2808399)
5. Rejects the packet if latitude/longitude fall outside ±90/±180 (`GenericLocation.isValidCoordinate`) or altitude falls outside `GenericLocation.plausibleAltitudeRange` (-2,000..60,000 ft)
6. Converts speed from m/s to knots (×1.9438445) and normalizes track to 0..<360
7. `processXGPSData` updates both `XGPSDataReader` and `GenericLocation` states (only when X-Plane is selected source)

**Why a raw BSD socket instead of `NWListener`:** `NWListener`'s UDP mode creates a per-sender `NWConnection` by internally `connect()`-ing a socket to the remote address ("established-over-unconnected"). On BSD-derived kernels, a connected socket takes delivery priority over other apps' plain wildcard-bound listening sockets on the same port, so this used to silently steal X-Plane's broadcast packets away from apps like ForeFlight running at the same time. `XGPSDataReader.startListening()` (XGPSDataReader.swift:26-52) instead uses a `UDPReceiver` (UDPReceiveLoop.swift), which opens a raw socket with `SO_REUSEADDR`/`SO_REUSEPORT`, binds to `INADDR_ANY:49002`, and only ever calls `recvfrom()` on a dedicated background `Thread` — never `connect()` — so it behaves like a normal passive listener and coexists with other apps.

### GDL90 Protocol Integration
The GDL90 protocol is a standard aviation data link protocol used by many portable GPS and ADS-B receivers. The implementation (GDL90Reader.swift):

**Receiving:** Uses the same `UDPReceiver` raw BSD socket / `recvfrom()` approach as `XGPSDataReader` (GDL90Reader.swift:71-113) for the same reason — avoids stealing UDP broadcast packets from other GDL90-consuming apps on port 4000. The outbound heartbeat broadcast (below) is unaffected and still uses `NWConnection`, since sending isn't subject to this issue.

**Framing and Validation:**
- Messages framed with 0x7E flag bytes
- Byte stuffing: 0x7D escape byte followed by XOR 0x20
- CRC-16-CCITT validation with table-driven lookup (polynomial 0x1021). Note this is the GDL90 spec's own variant (`crc = Table[crc >> 8] ^ (crc << 8) ^ byte`), not standard CRC-16/CCITT, which folds the data byte into the table index instead
- Validates CRC before processing any message
- Framing, unstuffing, CRC rejection and field decoding are covered by the "GDL90 Parser Tests" suite (`VirtualPAPITests/GDL90ParserTests.swift`), which drives the internal `processGDL90Data(_:)` with frames built by its own `GDL90TestFrame` helper. That helper derives the CRC table from the polynomial instead of reusing `GDL90Reader`'s hard-coded one, and is anchored to the heartbeat example in the spec, so a wrong table in either place would fail

**Message Parsing:**
- Message ID 10 (Ownship Report): Position, pressure altitude, ground speed, track
  - 24-bit signed lat/lon with LSB = 180/2^23 degrees; reports with latitude outside ±90 (the field spans ±180) are dropped via `GenericLocation.isValidCoordinate`
  - 12-bit altitude with 25 ft resolution, -1000 ft offset
  - 12-bit velocity with 1 knot resolution (0xFFF = invalid)
  - 8-bit track with LSB = 360/256 = 1.40625 degrees
  - Byte 12 low nibble ("misc"): its two low bits are the track type, decoded by `static func GDL90Reader.decodeTrackType(_:)` into `GDL90TrackType` (not valid / true track / magnetic heading / true heading). The raw track and its type are always published for the debug view, but `static func guidanceTrack(_:type:)` only passes the track to `GenericLocation` when it is a true track, otherwise nil (so the bearing arrow disappears, as for an invalid internal GPS course): relative bearing is computed against true bearings, so a magnetic heading would be off by the local variation, and a heading ignores wind drift
  - Byte 13 upper nibble: NIC (Navigation Integrity Category), published as `nic`. Reports with NIC below `GDL90Reader.minimumNIC` (1) are published but not fed to `GenericLocation`: per the spec a device without a fix sends lat/lon 0 with NIC 0, which `isValidCoordinate` accepts and would otherwise put the aircraft at Null Island while looking fresh
- Message ID 0 (Heartbeat): byte 1 bit 7 ("GPS Pos Valid") is published as `deviceGPSValid` (nil until a heartbeat arrives, reset by `stopListening()`); status only, shown in GDL90DebugView, it doesn't gate guidance
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
- Sending to `255.255.255.255` on iOS 14+ requires the local network permission (`NSLocalNetworkUsageDescription`) and the Apple-managed `com.apple.developer.networking.multicast` entitlement; without the entitlement the `NWConnection` fails. The result of each heartbeat is published as `GDL90Reader.heartbeatStatus` (`HeartbeatStatus`: idle / waiting(reason) / sent / failed(reason); reset to idle by `stopListening()`) and shown as the "Heartbeat" row in GDL90DebugView

### Airport Selection and Target Calculation
The `AirportSelection` class (AirportSelection.swift) manages destination configuration:
- Stores selected airport and runway
- Calculates final aiming point using `calculateAimingPoint()` (AirportSelection.swift:94-147), which returns `nil` when no runway is selected; `setTargets()` is likewise a no-op then, so a stray change notification (e.g. the aiming point slider's `.onChange` in AirportSelectionView) can't act on a cleared selection
- `clear()` resets `aimingPoint` (and `descentAngle`) *before* nil'ing the airport/runway, so the `.onChange` that assignment triggers still sees a consistent selection
- Accounts for displaced threshold + user-specified aiming point (default 500 ft)
- Uses great circle calculation to project target point along runway heading
- Updates `GenericLocation` with target coordinates for distance/bearing calculations

### Glide Slope Calculation
The glide slope deviation logic (GenericLocation.swift:222-244):
- Configurable descent angle (default 3.0°, stored in `AirportSelection.descentAngle`)
- Calculates actual angle: `atan((altitude - targetElevation) / distanceInFeet) * 180 / π`
- Deviation = actual angle - desired descent angle
- Backstop: if distance is not positive or the deviation is non-finite, `updateAngleToDestination()` keeps the previous values, so NaN can never enter the EMA (which would otherwise stay NaN until `reset()` and peg the indicator, since `min`/`max` clamping doesn't catch NaN)
- `updateLocationInfo()` and the helpers it calls (`updateAngleToDestination()`, `updateVerticalSpeedToDestination()`, `updateBearingToDestination()`) each guard on the optional target latitude/longitude/elevation and simply return when one is missing, instead of force-unwrapping what `updateLocationInfo()` already checked
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

### Logging
- Never use `print`: all diagnostics go through `os.Logger`, via the categories in `VirtualPAPI/Log.swift` (`Logger.guidance`, `.internalGPS`, `.xgps`, `.gdl90`, `.udp`, `.database`; subsystem `com.mfdutra.VirtualPAPI`). The extension is `nonisolated` so the UDP receive threads and the database queue can use it
- Levels: `.debug` for per-update chatter (e.g. the 1 Hz "Deviation:" line in `updateAngleToDestination()`, essentially free when nothing is capturing), `.info` for routine events, `.notice` for state changes worth keeping (database copied/updated), `.error` for failures, `.fault` for "should never happen" (a UDP receive thread that won't exit)
- Dynamic strings are redacted in logs read off a device, so interpolate values needed to diagnose a user report (errors, labels, paths) with `privacy: .public`; numbers are public by default
- Interpolations are autoclosures, so instance properties need an explicit `self.` inside a closure (as in `UDPReceiver`'s receive thread)
- Read logs from a device with Console.app (filter on the subsystem) or `log stream --predicate 'subsystem == "com.mfdutra.VirtualPAPI"' --level debug`

### Unit Tests
Tests use Swift Testing. `.serialized` only orders tests *within* a suite; separate suites still run in parallel, so any state shared across suites is a race. In particular, never construct `AppSettings()` in tests: it reads and writes `UserDefaults.standard`, and a setter in one suite (e.g. `locationSource = .xPlane`) can leak into another suite's "default values" assertions. Use `AppSettings(defaults: .isolatedForTesting())` (a fresh, UUID-named suite), or, in `AppSettingsTests`, the per-test `defaults` store that the suite's `init`/`deinit` create and remove.

Tests that construct or touch a main-actor-isolated type (`GenericLocation`, `AirportSelection`, the readers) must be annotated `@MainActor` — on the suite (as `XGPSDataReaderTests` does) or on the individual test. Without it an `async` test body lands in a nonisolated context and every property access warns ("main actor-isolated property ... can not be mutated from a nonisolated context"), which is an error in the Swift 6 language mode. Once the test is `@MainActor`, drop the `await` on synchronous isolated calls such as `selection.setTargets()`, or it warns in turn about a redundant `await`.

Test files: `VirtualPAPITests/VirtualPAPITests.swift` (everything except GDL90 framing and internal GPS), `VirtualPAPITests/GDL90ParserTests.swift` (GDL90 wire-format parsing plus the `GDL90TestFrame` frame builder) and `VirtualPAPITests/LocationTrackerTests.swift` (the "Internal GPS Validity Tests", "Vertical Accuracy Caution Tests" and "Internal GPS Diagnostics Tests" suites, which drive `HighFrequencyLocationTracker`'s `didUpdateLocations` with synthesized `CLLocation`s; since the delegate hands the fix to the main queue, those tests `await Task.yield()` until it lands). The test target is a file-system synchronized group, so new files in `VirtualPAPITests/` are picked up without editing the project file.

### Concurrency
- `XGPSDataReader` and `GDL90Reader` use `@MainActor` to ensure all UI updates happen on main thread
- UDP receiving uses raw BSD sockets (`socket`/`bind`/`recvfrom`), each with its own dedicated background `Thread` running a blocking receive loop — not `NWListener`/`DispatchQueue`, to avoid the socket-priority issue described above
- Both readers own their sockets through `nonisolated final class UDPReceiver` (UDPReceiveLoop.swift): `UDPReceiver.open(port:label:)` creates, configures and binds the socket plus a self-pipe, `start(onDatagram:onUnexpectedExit:)` spawns the receive thread, `stop()` shuts it down. `XGPSDataReader` keeps one (`receiver`), `GDL90Reader` an array (`receivers`, one per port); neither touches a raw descriptor
- The loop `poll()`s the socket and the pipe's read end together, so it sleeps until something happens (no timeout polling, no busy-waiting). It skips zero-length datagrams (for UDP, `recvfrom` returning 0 is an empty datagram, not EOF), retries on `EINTR`/`EAGAIN`/`EWOULDBLOCK`, and otherwise returns `true` when woken by the pipe (deliberate stop) or `false` on a fatal socket error (logged)
- **Shutdown protocol.** `stop()` writes one byte to the pipe, waits (bounded, 2 s) for the receive thread to signal a `DispatchSemaphore` as it finishes, and only then closes the socket and the pipe. Closing a descriptor does *not* reliably interrupt a `recvfrom()` already blocked on it on Darwin, so closing first could leave the thread parked on a descriptor number the kernel later recycles for something else. `stop()` is idempotent, safe before `start()`, and returns with the port free, so stop → start restarts (including GDL90's two ports) work immediately. In the unreachable case where the thread doesn't exit in time, the descriptors are deliberately leaked (and logged) rather than recycled
- No deadlock: the receive thread signals the semaphore *before* invoking `onUnexpectedExit`, and both readers' callbacks only enqueue `Task { @MainActor ... }`, so a `stop()` called from the main actor never waits on work that needs the main actor. Those `Task`s repeat the `[weak self]` capture (`Task { @MainActor [weak self] in ... }`) rather than reading the enclosing closure's weak `self`: a weak capture is a mutable var, and referencing it from the concurrently-executing `Task` is an error in the Swift 6 language mode. The thread also holds a strong reference to its `UDPReceiver`, so the descriptors stay valid for as long as the loop can use them
- `onUnexpectedExit` fires only when the loop ended on its own, so a deliberate stop stays quiet. It hops to the main actor and re-checks that the receiver is still registered (compared by identity, since `stopListening()` clears the references first): `XGPSDataReader` calls `stopListening()` (so `isConnected = false`); `GDL90Reader` drops and stops just that receiver, and calls `stopListening()` (which sets `isConnected = false` and stops the heartbeat) only once no receive loops remain, since 4000 and 43211 are independent
- Covered by the "UDP Receiver Tests" and "Listener Lifecycle Tests" suites (delivery, prompt stop, restart cycles, idempotent stop, quiet deliberate stop, `isConnected` across start/stop cycles)
- `GDL90Reader` still keeps `DispatchQueue(label: "gdl90-udp-queue")` for its outbound heartbeat broadcast (`NWConnection`-based `sendBroadcast()`), which is unrelated to receiving
- Location updates use `Task { @MainActor in ... }` to hop back from the receive thread for thread-safe UI updates
- Repeating timers (GenericLocation's 1 Hz update and 5 s staleness check, GDL90Reader's heartbeat) are created with `Timer(timeInterval:repeats:block:)` and added via `RunLoop.main.add(_, forMode: .common)`, not `Timer.scheduledTimer`, which installs in `.default` mode only and stops firing while the main run loop is in tracking mode (scrolling, dragging a slider) — freezing the guidance display. Add any new timer the same way
- `DatabaseManager` is synchronous and callable from any thread/actor: all SQLite access is serialized on its private serial `DispatchQueue` (see "Database Management"). `downloadRemoteDatabase()` is `async` and `@concurrent`; the only main-actor hop is `getRemoteDatabaseURL()`, because `Secrets` is main-actor isolated by default
- Note: the app *and test* targets build with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so unannotated types are main-actor isolated; types meant to be used off the main thread must be explicitly `nonisolated`. This extends to individual members: `GenericLocation.plausibleAltitudeRange` and `GenericLocation.isValidCoordinate(latitude:longitude:)` are pure validators called from the `nonisolated` packet parsers, so both are marked `nonisolated`

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
- **Privacy strings** (generated Info.plist via `INFOPLIST_KEY_*` build settings, Debug and Release): `NSLocationWhenInUseUsageDescription` (internal GPS) and `NSLocalNetworkUsageDescription` (UDP listeners on 4000/43211/49002 and the GDL90 heartbeat broadcast). `NSBonjourServices` is not needed since the app uses plain UDP, not Bonjour
- **Entitlements**: none yet. The GDL90 heartbeat broadcast needs `com.apple.developer.networking.multicast`, which must be requested from Apple; once granted, add `VirtualPAPI/VirtualPAPI.entitlements` with that key set to true and point `CODE_SIGN_ENTITLEMENTS` at it (adding it before the grant breaks signing)
