# Changelog

All notable changes to VirtualPAPI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
