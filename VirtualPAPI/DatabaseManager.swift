//
//  DatabaseManager.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import CryptoKit
import Foundation
import SQLite3

// MARK: - String Extension for Base32 Decoding

extension String {
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

class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?

    private init() {
        ensureDatabaseIsUpToDate()
        openDatabase()
    }

    deinit {
        closeDatabase()
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

    /// Download the aviation database from remote server with ETag caching
    /// - Returns: True if database was updated, false if already up-to-date
    @discardableResult
    func downloadRemoteDatabase() async throws -> Bool {
        guard let url = getRemoteDatabaseURL() else {
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

        // Download
        let (data, response) = try await session.data(for: request)

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

        // Close the current database
        closeDatabase()

        // Write new database to Documents directory
        let documentsPath = getDocumentsDatabasePath()
        try data.write(to: URL(fileURLWithPath: documentsPath))

        // Store the new ETag for future requests
        if let newETag = httpResponse.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(newETag, forKey: etagKey)
        }

        // Store download timestamp
        UserDefaults.standard.set(Date(), forKey: "last_database_download")

        // Reopen the database
        openDatabase()

        print("Database updated successfully")
        return true
    }

    // MARK: - Database Errors

    enum DatabaseError: Error {
        case invalidURL
        case invalidResponse
        case httpError(Int)
    }

    private func openDatabase() {
        // Open database from Documents directory
        let dbPath = getDocumentsDatabasePath()

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database at \(dbPath)")
            return
        }

        print("Database opened successfully at \(dbPath)")
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    // Get a specific airport by its identifier
    func getAirport(ident: String) -> Airport? {
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
            sqlite3_bind_text(
                statement,
                1,
                (ident as NSString).utf8String,
                -1,
                nil
            )

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

    // Search airports by ICAO code or name
    func searchAirports(query: String) -> [Airport] {
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
            sqlite3_bind_text(
                statement,
                1,
                (searchPattern as NSString).utf8String,
                -1,
                nil
            )
            sqlite3_bind_text(
                statement,
                2,
                (searchPattern as NSString).utf8String,
                -1,
                nil
            )
            sqlite3_bind_text(
                statement,
                3,
                (searchPattern as NSString).utf8String,
                -1,
                nil
            )
            sqlite3_bind_text(
                statement,
                4,
                (searchPattern as NSString).utf8String,
                -1,
                nil
            )
            sqlite3_bind_text(
                statement,
                5,
                (searchPattern as NSString).utf8String,
                -1,
                nil
            )

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

    // Get runways for a specific airport
    func getRunways(forAirport airportIdent: String) -> [Runway] {
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
            sqlite3_bind_text(
                statement,
                1,
                (airportIdent as NSString).utf8String,
                -1,
                nil
            )

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

    // Get row counts for airports and runways tables
    func getTableRowCounts() -> (airports: Int, runways: Int) {
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
