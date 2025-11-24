//
//  DatabaseManager.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

import Foundation
import SQLite3

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
}
