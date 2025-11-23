#!/usr/bin/env python3
"""
Generate SQLite database from airports and runways CSV files.
Data from https://ourairports.com/data/
"""

import argparse
import sqlite3
import csv
import os

global args


def create_database(db_path='aviation.db'):
    """Create SQLite database with airports and runways tables."""

    # Remove existing database if it exists
    if os.path.exists(db_path):
        os.remove(db_path)
        print(f"Removed existing database: {db_path}")

    # Create connection
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Create airports table
    cursor.execute('''
        CREATE TABLE airports (
            ident TEXT PRIMARY KEY,
            name TEXT,
            iata_code TEXT,
            latitude_deg REAL,
            longitude_deg REAL,
            elevation_ft INTEGER,
            local_code TEXT,
            gps_code TEXT,
            icao_code TEXT
        )
    ''')
    print("Created airports table")

    # Create runways table
    cursor.execute('''
        CREATE TABLE runways (
            airport_ident TEXT,
            ident TEXT,
            length_ft INTEGER,
            width_ft INTEGER,
            latitude_deg REAL,
            longitude_deg REAL,
            elevation_ft INTEGER,
            heading_degT REAL,
            displaced_threshold_ft INTEGER,
            PRIMARY KEY (airport_ident, ident)
        )
    ''')
    print("Created runways table")

    # Load airports data
    print("Loading airports data...")
    with open(args.airports, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        airports_data = []
        for row in reader:
            airports_data.append((
                row['ident'],
                row['name'],
                row['iata_code'] if row['iata_code'] else None,
                float(row['latitude_deg']) if row['latitude_deg'] else None,
                float(row['longitude_deg']) if row['longitude_deg'] else None,
                int(row['elevation_ft']) if row['elevation_ft'] else None,
                row['local_code'] if row['local_code'] else None,
                row['gps_code'] if row['gps_code'] else None,
                row['icao_code'] if row['icao_code'] else None,
            ))

        cursor.executemany('''
            INSERT INTO airports VALUES (?,?,?,?,?,?,?,?,?)
        ''', airports_data)
        print(f"Loaded {len(airports_data)} airports")

    # Load runways data
    print("Loading runways data...")
    with open(args.runways, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Add one row for each side of the runway

            if (not row['le_latitude_deg']) or (not row['le_longitude_deg']) or \
                    (not row['he_latitude_deg']) or (not row['he_longitude_deg']):
                continue  # Skip runways with missing end coordinates

            if (not row['le_ident']) or (not row['he_ident']):
                continue  # Skip runways with missing identifiers

            if row['le_ident'] == "XX" or row['he_ident'] == "XX":
                continue  # Skip invalid runway identifiers

            side1 = (
                row['airport_ident'],
                row['le_ident'],
                int(row['length_ft']) if row['length_ft'] else None,
                int(row['width_ft']) if row['width_ft'] else None,
                float(row['le_latitude_deg']
                      ),
                float(row['le_longitude_deg']
                      ),
                int(row['le_elevation_ft']) if row['le_elevation_ft'] else None,
                float(row['le_heading_degT']
                      ) if row['le_heading_degT'] else None,
                int(row['le_displaced_threshold_ft']
                    ) if row['le_displaced_threshold_ft'] else 0,
            )

            side2 = (
                row['airport_ident'],
                row['he_ident'],
                int(row['length_ft']) if row['length_ft'] else None,
                int(row['width_ft']) if row['width_ft'] else None,
                float(row['he_latitude_deg']
                      ),
                float(row['he_longitude_deg']
                      ),
                int(row['he_elevation_ft']) if row['he_elevation_ft'] else None,
                float(row['he_heading_degT']
                      ) if row['he_heading_degT'] else None,
                int(row['he_displaced_threshold_ft']
                    ) if row['he_displaced_threshold_ft'] else 0
            )

            for side in (side1, side2):
                try:
                    cursor.execute('''
                        INSERT INTO runways VALUES (?,?,?,?,?,?,?,?,?)
                    ''', side)

                except Exception as e:
                    print(f"Error inserting runway {side}: {e}")
                    raise

    # Create indexes for better query performance
    print("Creating indexes...")
    cursor.execute(
        'CREATE INDEX idx_runways_airport_ident ON runways(airport_ident)')

    for col in ['iata_code', 'local_code', 'gps_code', 'icao_code']:
        cursor.execute(
            f'CREATE INDEX idx_airports_{col} ON airports({col})')

    # Remove airports without associated runways
    print("Removing airports without runways...")
    cursor.execute('''
        DELETE FROM airports
        WHERE ident NOT IN (SELECT DISTINCT airport_ident FROM runways)
    ''')
    removed_count = cursor.rowcount
    print(f"Removed {removed_count} airports without runways")

    # Commit and close
    conn.commit()
    cursor.execute('VACUUM')
    print(f"\nDatabase created successfully: {db_path}")

    # Print some statistics
    cursor.execute('SELECT COUNT(*) FROM airports')
    airport_count = cursor.fetchone()[0]
    cursor.execute('SELECT COUNT(*) FROM runways')
    runway_count = cursor.fetchone()[0]

    print(f"Total airports: {airport_count}")
    print(f"Total runways: {runway_count}")

    conn.close()


def get_args():
    parser = argparse.ArgumentParser(
        description="Generate SQLite database from airports and runways CSV files.")
    parser.add_argument('airports', help='Path to airports CSV file')
    parser.add_argument('runways', help='Path to runways CSV file')
    return parser.parse_args()


if __name__ == '__main__':
    args = get_args()
    create_database()
