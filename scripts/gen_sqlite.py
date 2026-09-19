#!/usr/bin/env python3
"""
Generate SQLite database from airports and runways CSV files.
Data from https://ourairports.com/data/
"""

import argparse
import sqlite3
import csv
import math
import os
import tempfile
from collections import Counter


def initial_bearing(lat1, lon1, lat2, lon2):
    """True initial great-circle bearing (0-360) from point 1 to point 2."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dlon = math.radians(lon2 - lon1)
    y = math.sin(dlon) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - \
        math.sin(phi1) * math.cos(phi2) * math.cos(dlon)
    return round(math.degrees(math.atan2(y, x)) % 360, 1)


def heading(csv_heading, from_lat, from_lon, to_lat, to_lon):
    """CSV heading when present, else computed from the runway end coordinates."""
    if csv_heading:
        return float(csv_heading)
    return initial_bearing(from_lat, from_lon, to_lat, to_lon)


def build_database(db_path, airports_csv, runways_csv):
    """Populate a fresh SQLite database at db_path. Returns a Counter of stats."""

    stats = Counter()

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
    with open(airports_csv, 'r', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))

        # The app reads coordinates as non-optional doubles, so an airport
        # without them would silently end up at 0,0 (Null Island)
        located = [row for row in rows
                   if row['latitude_deg'] and row['longitude_deg']]
        stats['airports_without_coordinates'] = len(rows) - len(located)

        airports_data = [(
            row['ident'],
            row['name'],
            row['iata_code'] if row['iata_code'] else None,
            float(row['latitude_deg']),
            float(row['longitude_deg']),
            int(row['elevation_ft']) if row['elevation_ft'] else None,
            row['local_code'] if row['local_code'] else None,
            row['gps_code'] if row['gps_code'] else None,
            row['icao_code'] if row['icao_code'] else None,
        ) for row in located]

        cursor.executemany('''
            INSERT INTO airports VALUES (?,?,?,?,?,?,?,?,?)
        ''', airports_data)
        print(f"Loaded {len(airports_data)} airports")

    # Load runways data
    print("Loading runways data...")
    with open(runways_csv, 'r', encoding='utf-8') as f:
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

            if row["closed"] == "1":
                continue  # Skip closed runways

            le_lat, le_lon = float(row['le_latitude_deg']), float(row['le_longitude_deg'])
            he_lat, he_lon = float(row['he_latitude_deg']), float(row['he_longitude_deg'])

            if (le_lat, le_lon) == (he_lat, he_lon):
                continue  # Skip runways whose ends share identical coordinates

            side1 = (
                row['airport_ident'],
                row['le_ident'],
                int(row['length_ft']) if row['length_ft'] else None,
                int(row['width_ft']) if row['width_ft'] else None,
                le_lat,
                le_lon,
                int(row['le_elevation_ft']) if row['le_elevation_ft'] else None,
                heading(row['le_heading_degT'], le_lat, le_lon, he_lat, he_lon),
                int(row['le_displaced_threshold_ft']
                    ) if row['le_displaced_threshold_ft'] else 0,
            )

            side2 = (
                row['airport_ident'],
                row['he_ident'],
                int(row['length_ft']) if row['length_ft'] else None,
                int(row['width_ft']) if row['width_ft'] else None,
                he_lat,
                he_lon,
                int(row['he_elevation_ft']) if row['he_elevation_ft'] else None,
                heading(row['he_heading_degT'], he_lat, he_lon, le_lat, le_lon),
                int(row['he_displaced_threshold_ft']
                    ) if row['he_displaced_threshold_ft'] else 0
            )

            sides = ((side1, row['le_heading_degT']),
                     (side2, row['he_heading_degT']))

            # Skip runway ends without elevation data (index 6 is elevation_ft)
            for side, csv_heading in sides:
                if side[6] is None:
                    stats['ends_without_elevation'] += 1
                    continue

                try:
                    cursor.execute('''
                        INSERT INTO runways VALUES (?,?,?,?,?,?,?,?,?)
                    ''', side)

                except sqlite3.IntegrityError:
                    # Two ends with the same identifier at the same airport:
                    # keep the first and carry on rather than abort the build
                    stats['duplicate_ends'] += 1
                    print(f"Warning: skipping duplicate runway end "
                          f"{side[0]}/{side[1]}")
                    continue

                if not csv_heading:
                    stats['headings_backfilled'] += 1

    # Create indexes for better query performance
    print("Creating indexes...")
    cursor.execute(
        'CREATE INDEX idx_runways_airport_ident ON runways(airport_ident)')

    for col in ['iata_code', 'local_code', 'gps_code', 'icao_code']:
        cursor.execute(
            f'CREATE INDEX idx_airports_{col} ON airports({col})')

    # Remove runways whose airport was filtered out above
    cursor.execute('''
        DELETE FROM runways
        WHERE airport_ident NOT IN (SELECT ident FROM airports)
    ''')
    stats['orphaned_runways'] = cursor.rowcount

    # Remove airports without associated runways
    print("Removing airports without runways...")
    cursor.execute('''
        DELETE FROM airports
        WHERE ident NOT IN (SELECT DISTINCT airport_ident FROM runways)
    ''')
    stats['airports_without_runways'] = cursor.rowcount
    print(f"Removed {stats['airports_without_runways']} airports without runways")

    # Commit and close
    conn.commit()
    cursor.execute('VACUUM')

    cursor.execute('SELECT COUNT(*) FROM airports')
    stats['airports'] = cursor.fetchone()[0]
    cursor.execute('SELECT COUNT(*) FROM runways')
    stats['runways'] = cursor.fetchone()[0]

    conn.close()
    return stats


def create_database(db_path, airports_csv, runways_csv):
    """Build the database out of line and move it into place when complete."""

    # Build into a temporary file next to the destination so that an aborted
    # run can never leave a partial aviation.db behind
    fd, tmp_path = tempfile.mkstemp(
        prefix='.gen_sqlite-', suffix='.db',
        dir=os.path.dirname(os.path.abspath(db_path)))
    os.close(fd)

    try:
        stats = build_database(tmp_path, airports_csv, runways_csv)
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, db_path)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    print(f"\nDatabase created successfully: {db_path}")
    print(f"Total airports: {stats['airports']}")
    print(f"Total runways: {stats['runways']}")
    print(f"Airports skipped (no coordinates): "
          f"{stats['airports_without_coordinates']}")
    print(f"Airports removed (no runways): {stats['airports_without_runways']}")
    print(f"Runways removed (no airport): {stats['orphaned_runways']}")
    print(f"Runway ends skipped (no elevation): "
          f"{stats['ends_without_elevation']}")
    print(f"Runway ends skipped (duplicate identifier): "
          f"{stats['duplicate_ends']}")
    print(f"Runway headings backfilled: {stats['headings_backfilled']}")

    return stats


def get_args():
    parser = argparse.ArgumentParser(
        description="Generate SQLite database from airports and runways CSV files.")
    parser.add_argument('airports', help='Path to airports CSV file')
    parser.add_argument('runways', help='Path to runways CSV file')
    parser.add_argument('-o', '--output', default='aviation.db',
                        help='Path of the SQLite database to write '
                             '(default: %(default)s)')
    return parser.parse_args()


if __name__ == '__main__':
    args = get_args()
    create_database(args.output, args.airports, args.runways)
