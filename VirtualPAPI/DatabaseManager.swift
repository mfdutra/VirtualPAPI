//
//  DatabaseManager.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import CryptoKit
import Foundation
import SQLite3

/// Tells SQLite to copy the bound value, so it doesn't have to outlive the
/// `sqlite3_bind_*` call (SQLITE_STATIC would promise that it does).
private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

// MARK: - String Extension for Base32 Decoding

nonisolated extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let stringLength = self.count
        if stringLength < toLength {
            return String(
                repeatElement(character, count: toLength - stringLength)
            ) + self
        } else {
            return self
        }
    }
}

// MARK: - DatabaseManager

/// Thread-safe: every access to the SQLite handle (`db`) — open, close, all
/// queries, and the close→replace→reopen during a remote update — runs on
/// the private serial `queue`, so callers on any thread/actor wait for each
/// other instead of racing on the handle. Public methods wrap `queue.sync`;
/// private helpers that touch `db` assume they're already on `queue` (they
/// must never call `queue.sync` themselves, which would deadlock).
nonisolated final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private let queue = DispatchQueue(label: "database-manager-queue")

    // Only accessed on `queue`
    private var db: OpaquePointer?

    private init() {
        queue.sync {
            ensureDatabaseIsUpToDate()
            openDatabase()
        }
    }

    deinit {
        queue.sync { closeDatabase() }
    }

    /// Ensures the database in Documents directory exists and is up-to-date with the bundle version
    private func ensureDatabaseIsUpToDate() {
        let fileManager = FileManager.default

        // Get path to database in bundle
        guard
            let bundlePath = Bundle.main.path(
                forResource: "aviation",
                ofType: "db"
            )
        else {
            print("Error: Unable to find aviation.db in bundle")
            return
        }

        // Get path to database in Documents directory
        let documentsPath = getDocumentsDatabasePath()

        // Check if database exists in Documents
        if fileManager.fileExists(atPath: documentsPath) {
            // Compare modification dates to see if bundle is newer
            do {
                let bundleAttributes = try fileManager.attributesOfItem(
                    atPath: bundlePath
                )
                let documentsAttributes = try fileManager.attributesOfItem(
                    atPath: documentsPath
                )

                if let bundleDate = bundleAttributes[.modificationDate]
                    as? Date,
                    let documentsDate = documentsAttributes[.modificationDate]
                        as? Date
                {

                    if bundleDate > documentsDate {
                        print(
                            "Bundle database is newer, updating Documents version..."
                        )
                        try copyDatabaseToDocuments(
                            from: bundlePath,
                            to: documentsPath
                        )
                    } else {
                        print("Documents database is up-to-date")
                    }
                }
            } catch {
                print("Error comparing database versions: \(error)")
                // If comparison fails, try to copy anyway
                do {
                    try copyDatabaseToDocuments(
                        from: bundlePath,
                        to: documentsPath
                    )
                } catch {
                    print("Error copying database: \(error)")
                }
            }
        } else {
            // Database doesn't exist in Documents, copy it
            print("Copying aviation.db to Documents directory...")
            do {
                try copyDatabaseToDocuments(from: bundlePath, to: documentsPath)
                print("Database copied successfully")
            } catch {
                print("Error copying database to Documents: \(error)")
            }
        }
    }

    /// Get the path to the database in the Documents directory
    private func getDocumentsDatabasePath() -> String {
        let paths = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent("aviation.db").path
    }

    /// Copy database from bundle to Documents directory
    private func copyDatabaseToDocuments(
        from sourcePath: String,
        to destinationPath: String
    ) throws {
        let fileManager = FileManager.default

        // Remove existing database if present
        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }

        // Copy the database
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    // MARK: - Remote Database Download

    /// Generates a TOTP (Time-Based One-Time Password) code
    private func generateTOTP(secret: String, time: Date = Date()) -> String? {
        // Decode base32 secret
        guard let secretData = base32Decode(secret) else {
            return nil
        }

        // Get time counter (Unix timestamp / 30)
        let counter = UInt64(time.timeIntervalSince1970 / 30)

        // Convert counter to big-endian bytes
        var counterBytes = counter.bigEndian
        let counterData = Data(
            bytes: &counterBytes,
            count: MemoryLayout<UInt64>.size
        )

        // Generate HMAC-SHA1
        let key = SymmetricKey(data: secretData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(
            for: counterData,
            using: key
        )

        // Dynamic truncation
        let hmacData = Data(hmac)
        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)

        let truncatedHash = hmacData.subdata(in: offset..<offset + 4)
        var number = truncatedHash.withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        number &= 0x7fff_ffff
        number = number % 1_000_000

        // Return 6-digit code
        return String(format: "%06d", number)
    }

    /// Decode a base32 encoded string to Data
    private func base32Decode(_ string: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = ""

        let cleanString = string.uppercased().replacingOccurrences(
            of: "=",
            with: ""
        )

        for char in cleanString {
            guard let index = alphabet.firstIndex(of: char) else {
                return nil
            }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            bits += String(value, radix: 2).leftPadding(
                toLength: 5,
                withPad: "0"
            )
        }

        var data = Data()
        var index = bits.startIndex

        while bits.distance(from: index, to: bits.endIndex) >= 8 {
            let endIndex = bits.index(index, offsetBy: 8)
            let byteString = String(bits[index..<endIndex])
            if let byte = UInt8(byteString, radix: 2) {
                data.append(byte)
            }
            index = endIndex
        }

        return data
    }

    /// Constructs the remote database URL with TOTP authentication
    ///
    /// - Note: This function requires VirtualPAPI/Secrets.swift to be created locally.
    ///   This file is excluded from version control via .gitignore.
    ///   Create it with the following content:
    ///   ```swift
    ///   import Foundation
    ///   enum Secrets {
    ///       static let totpSecret = "YOUR_TOTP_SECRET_KEY"
    ///   }
    ///   ```
    ///   Replace YOUR_TOTP_SECRET_KEY with the actual base32-encoded TOTP secret.
    @MainActor  // Secrets is main-actor isolated (default isolation)
    private func getRemoteDatabaseURL() -> URL? {
        guard let totp = generateTOTP(secret: Secrets.totpSecret) else {
            print("Error: Failed to generate TOTP")
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "virtualpapi.net"
        components.path = "/update-aviation-db"
        components.queryItems = [
            URLQueryItem(name: "totp", value: totp)
        ]

        return components.url
    }

    // MARK: - Remote Database Update Limits

    /// Largest database file accepted from the remote server. The bundled
    /// database is ~3.5 MB; 50 MB leaves plenty of room for growth (e.g.
    /// including every OurAirports airport) while rejecting anything absurd.
    static let maxDatabaseSize: Int64 = 50 * 1024 * 1024

    /// Sanity floors for a downloaded database. The bundled database has
    /// ~11,400 airports and ~29,700 runways, so a legitimate update should
    /// never fall below roughly half of that.
    static let minAirportCount = 5_000
    static let minRunwayCount = 15_000

    /// Download the aviation database from remote server with ETag caching.
    ///
    /// The update is transactional: the file is downloaded to a staging file,
    /// validated with `validateDatabase(at:)`, and only then atomically swapped
    /// in for the live database. The previous database is kept as
    /// `aviation.db.bak` and restored if the new one can't be reopened. The
    /// ETag and download date are stored only after a successful swap.
    /// - Returns: True if database was updated, false if already up-to-date
    @discardableResult
    @concurrent
    func downloadRemoteDatabase() async throws -> Bool {
        guard let url = await getRemoteDatabaseURL() else {
            throw DatabaseError.invalidURL
        }

        // Create request with cache policy that ignores local cache
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.setValue("VirtualPAPI", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        // Add ETag if we have one from previous download
        let etagKey = "aviation_db_etag"
        if let storedETag = UserDefaults.standard.string(forKey: etagKey) {
            request.setValue(storedETag, forHTTPHeaderField: "If-None-Match")
        }

        // Create URLSession configuration that doesn't cache
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)

        // Download to a temporary file instead of into memory
        let (tempURL, response) = try await session.download(for: request)

        let fileManager = FileManager.default
        let liveURL = URL(fileURLWithPath: getDocumentsDatabasePath())
        let directory = liveURL.deletingLastPathComponent()
        // Staging file lives next to the live database so the final swap is
        // an atomic rename on the same volume.
        let stagingURL = directory.appendingPathComponent(
            "aviation.db.download"
        )
        let backupName = "aviation.db.bak"

        defer {
            try? fileManager.removeItem(at: tempURL)
            try? fileManager.removeItem(at: stagingURL)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DatabaseError.invalidResponse
        }

        // Check if not modified
        if httpResponse.statusCode == 304 {
            print("Database is up-to-date")
            return false
        }

        // Check for success
        guard httpResponse.statusCode == 200 else {
            throw DatabaseError.httpError(httpResponse.statusCode)
        }

        // Reject oversized downloads based on the advertised length (when
        // present) and on the actual size of the file we received.
        let advertisedSize = httpResponse.expectedContentLength
        if advertisedSize > Self.maxDatabaseSize {
            throw DatabaseError.tooLarge(advertisedSize)
        }
        let actualSize =
            (try? fileManager.attributesOfItem(atPath: tempURL.path)[.size]
                as? NSNumber)?.int64Value ?? 0
        if actualSize > Self.maxDatabaseSize {
            throw DatabaseError.tooLarge(actualSize)
        }

        try? fileManager.removeItem(at: stagingURL)
        try fileManager.moveItem(at: tempURL, to: stagingURL)

        // Validate before touching the live database
        try Self.validateDatabase(at: stagingURL)

        // Swap in the new database, keeping the previous one as a backup
        try replaceDatabase(with: stagingURL, backupName: backupName)

        // Only now record the ETag and download timestamp
        if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(newETag, forKey: etagKey)
        }
        UserDefaults.standard.set(Date(), forKey: "last_database_download")

        print("Database updated successfully")
        return true
    }

    // MARK: - Database Validation

    /// Validates that the file at `url` is a usable aviation database:
    /// SQLite header, `PRAGMA integrity_check`, the tables and columns the
    /// app queries, and minimum airport/runway counts.
    /// - Throws: `DatabaseError.invalidDatabase` describing the first problem.
    static func validateDatabase(
        at url: URL,
        minAirports: Int = minAirportCount,
        minRunways: Int = minRunwayCount
    ) throws {
        // 1. SQLite header magic
        let magic = Data("SQLite format 3\0".utf8)
        let header = try? FileHandle(forReadingFrom: url).read(
            upToCount: magic.count
        )
        guard header == magic else {
            throw DatabaseError.invalidDatabase("not an SQLite database")
        }

        // 2. Open read-only
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard
            sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
                == SQLITE_OK
        else {
            throw DatabaseError.invalidDatabase("could not be opened")
        }

        // 3. Integrity check
        guard scalarText(db, "PRAGMA integrity_check") == "ok" else {
            throw DatabaseError.invalidDatabase("integrity check failed")
        }

        // 4. Required tables and the columns the app reads
        let schemaQueries = [
            """
            SELECT ident, name, iata_code, latitude_deg, longitude_deg,
                   elevation_ft, local_code, gps_code, icao_code
            FROM airports LIMIT 0
            """,
            """
            SELECT airport_ident, ident, length_ft, width_ft, latitude_deg,
                   longitude_deg, elevation_ft, heading_degT,
                   displaced_threshold_ft
            FROM runways LIMIT 0
            """,
        ]
        guard schemaQueries.allSatisfy({ canPrepare(db, $0) }) else {
            throw DatabaseError.invalidDatabase("missing required tables")
        }

        // 5. Sanity floor on row counts
        let airports =
            scalarText(db, "SELECT COUNT(*) FROM airports").flatMap { Int($0) }
            ?? 0
        let runways =
            scalarText(db, "SELECT COUNT(*) FROM runways").flatMap { Int($0) }
            ?? 0
        guard airports >= minAirports, runways >= minRunways else {
            throw DatabaseError.invalidDatabase(
                "too few records (\(airports) airports, \(runways) runways)"
            )
        }
    }

    /// Returns the first column of the first row of `sql` as text, or nil.
    private static func scalarText(_ db: OpaquePointer?, _ sql: String)
        -> String?
    {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
            sqlite3_step(statement) == SQLITE_ROW,
            let text = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: text)
    }

    /// Whether `sql` compiles against the database (tables/columns exist).
    private static func canPrepare(_ db: OpaquePointer?, _ sql: String) -> Bool
    {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        return sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK
    }

    // MARK: - Database Errors

    enum DatabaseError: LocalizedError, Equatable {
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case tooLarge(Int64)
        case invalidDatabase(String)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not build the database update URL"
            case .invalidResponse:
                return "Invalid response from the update server"
            case .httpError(let code):
                return "Update server returned HTTP \(code)"
            case .tooLarge(let size):
                let formatted = ByteCountFormatter.string(
                    fromByteCount: size,
                    countStyle: .file
                )
                return "Downloaded database is too large (\(formatted))"
            case .invalidDatabase(let reason):
                return "Downloaded database is invalid: \(reason)"
            case .installFailed(let reason):
                return "Could not install the new database: \(reason)"
            }
        }
    }

    /// Swaps the validated database at `stagingURL` in for the live database
    /// in Documents, keeping the previous one as `backupName` and restoring
    /// it if the new database can't be opened.
    ///
    /// The close → swap → reopen runs as a single block on `queue`, so queries
    /// issued meanwhile wait rather than seeing a closed or half-written
    /// database. `stagingURL` must already have passed `validateDatabase(at:)`
    /// and must sit on the same volume as the live database for the swap to be
    /// atomic.
    func replaceDatabase(
        with stagingURL: URL,
        backupName: String = "aviation.db.bak"
    ) throws {
        let fileManager = FileManager.default
        let liveURL = URL(fileURLWithPath: getDocumentsDatabasePath())
        let backupURL = liveURL.deletingLastPathComponent()
            .appendingPathComponent(backupName)

        try queue.sync {
            closeDatabase()
            try? fileManager.removeItem(at: backupURL)
            do {
                _ = try fileManager.replaceItemAt(
                    liveURL,
                    withItemAt: stagingURL,
                    backupItemName: backupName,
                    options: .withoutDeletingBackupItem
                )
            } catch {
                openDatabase()
                throw DatabaseError.installFailed(error.localizedDescription)
            }

            guard openDatabase(),
                fetchTableRowCounts().airports >= Self.minAirportCount
            else {
                // Roll back to the previous database
                closeDatabase()
                _ = try? fileManager.replaceItemAt(
                    liveURL,
                    withItemAt: backupURL
                )
                openDatabase()
                throw DatabaseError.installFailed(
                    "The new database could not be opened"
                )
            }
        }
    }

    @discardableResult
    private func openDatabase() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))

        // Open database from Documents directory
        let dbPath = getDocumentsDatabasePath()

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database at \(dbPath)")
            return false
        }

        print("Database opened successfully at \(dbPath)")
        return true
    }

    private func closeDatabase() {
        dispatchPrecondition(condition: .onQueue(queue))

        if db != nil {
            // close_v2 never returns SQLITE_BUSY: if statements are still
            // open it defers the close instead of leaking the connection
            sqlite3_close_v2(db)
            db = nil
        }
    }

    // MARK: - Queries

    // Get a specific airport by its identifier
    func getAirport(ident: String) -> Airport? {
        queue.sync { fetchAirport(ident: ident) }
    }

    // Search airports by ICAO code or name
    func searchAirports(query: String) -> [Airport] {
        queue.sync { fetchAirports(query: query) }
    }

    // Get runways for a specific airport
    func getRunways(forAirport airportIdent: String) -> [Runway] {
        queue.sync { fetchRunways(forAirport: airportIdent) }
    }

    // Get row counts for airports and runways tables
    func getTableRowCounts() -> (airports: Int, runways: Int) {
        queue.sync { fetchTableRowCounts() }
    }

    // MARK: - Query implementations (must run on `queue`)

    private func fetchAirport(ident: String) -> Airport? {
        dispatchPrecondition(condition: .onQueue(queue))

        let queryString = """
                SELECT ident, name, latitude_deg, longitude_deg, elevation_ft
                FROM airports
                WHERE ident = ?
                LIMIT 1
            """

        var statement: OpaquePointer?
        var airport: Airport?

        if sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK
        {
            sqlite3_bind_text(statement, 1, ident, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                let ident = String(cString: sqlite3_column_text(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let latitude = sqlite3_column_double(statement, 2)
                let longitude = sqlite3_column_double(statement, 3)
                let elevation = sqlite3_column_double(statement, 4)

                airport = Airport(
                    ident: ident,
                    name: name,
                    latitude_deg: latitude,
                    longitude_deg: longitude,
                    elevation_ft: elevation
                )
            }
        }

        sqlite3_finalize(statement)
        return airport
    }

    private func fetchAirports(query: String) -> [Airport] {
        dispatchPrecondition(condition: .onQueue(queue))

        var airports: [Airport] = []

        let queryString = """
                SELECT ident, name, latitude_deg, longitude_deg, elevation_ft
                FROM airports
                WHERE ident LIKE ?
                OR iata_code LIKE ?
                OR local_code LIKE ?
                OR gps_code LIKE ?
                OR icao_code LIKE ?
                ORDER BY ident
                LIMIT 100
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK
        {
            let searchPattern = "\(query)%"
            sqlite3_bind_text(statement, 1, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, searchPattern, -1, SQLITE_TRANSIENT)

            while sqlite3_step(statement) == SQLITE_ROW {
                let ident = String(cString: sqlite3_column_text(statement, 0))
                let name = String(cString: sqlite3_column_text(statement, 1))
                let latitude = sqlite3_column_double(statement, 2)
                let longitude = sqlite3_column_double(statement, 3)
                let elevation = sqlite3_column_double(statement, 4)

                let airport = Airport(
                    ident: ident,
                    name: name,
                    latitude_deg: latitude,
                    longitude_deg: longitude,
                    elevation_ft: elevation
                )
                airports.append(airport)
            }
        }

        sqlite3_finalize(statement)
        return airports
    }

    private func fetchRunways(forAirport airportIdent: String) -> [Runway] {
        dispatchPrecondition(condition: .onQueue(queue))

        var runways: [Runway] = []

        let queryString = """
                SELECT ident, length_ft, width_ft, 
                       latitude_deg, longitude_deg, elevation_ft, 
                       heading_degT, displaced_threshold_ft
                FROM runways
                WHERE airport_ident = ?
                ORDER BY ident
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK
        {
            sqlite3_bind_text(statement, 1, airportIdent, -1, SQLITE_TRANSIENT)

            while sqlite3_step(statement) == SQLITE_ROW {
                let ident = String(cString: sqlite3_column_text(statement, 0))
                let length = sqlite3_column_double(statement, 1)
                let width = sqlite3_column_double(statement, 2)
                let latitude = sqlite3_column_double(statement, 3)
                let longitude = sqlite3_column_double(statement, 4)

                // Handle nullable columns
                let elevation: Double? =
                    sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 5)
                let heading: Double? =
                    sqlite3_column_type(statement, 6) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 6)

                let displacedThreshold = sqlite3_column_double(statement, 7)

                let runway = Runway(
                    airport_ident: airportIdent,
                    ident: ident,
                    length_ft: length,
                    width_ft: width,
                    latitude_deg: latitude,
                    longitude_deg: longitude,
                    elevation_ft: elevation,
                    heading_degT: heading,
                    displaced_threshold_ft: displacedThreshold
                )
                runways.append(runway)
            }
        }

        sqlite3_finalize(statement)
        return runways
    }

    private func fetchTableRowCounts() -> (airports: Int, runways: Int) {
        dispatchPrecondition(condition: .onQueue(queue))

        var airportCount = 0
        var runwayCount = 0

        // Count airports
        let airportQuery = "SELECT COUNT(*) FROM airports"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, airportQuery, -1, &statement, nil)
            == SQLITE_OK
        {
            if sqlite3_step(statement) == SQLITE_ROW {
                airportCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)

        // Count runways
        let runwayQuery = "SELECT COUNT(*) FROM runways"
        statement = nil

        if sqlite3_prepare_v2(db, runwayQuery, -1, &statement, nil)
            == SQLITE_OK
        {
            if sqlite3_step(statement) == SQLITE_ROW {
                runwayCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)

        return (airports: airportCount, runways: runwayCount)
    }
}
