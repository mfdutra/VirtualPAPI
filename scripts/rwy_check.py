#!/usr/bin/env python3
"""
rwy_check.py — Generate a KML file from airport and runway data.

Usage: ./rwy_check.py <sqlite_file> <airport_ident>
"""

import argparse
import math
import sqlite3
import sys

import simplekml

EARTH_RADIUS_M = 6371000.0
FT_TO_M = 0.3048


def project_point(lat_deg: float, lon_deg: float, heading_deg: float, distance_ft: float) -> tuple[float, float]:
    """Project a point distance_ft along heading_deg from (lat_deg, lon_deg)."""
    dist_m = distance_ft * FT_TO_M
    ang = dist_m / EARTH_RADIUS_M
    hdg = math.radians(heading_deg)
    lat = math.radians(lat_deg)
    lon = math.radians(lon_deg)

    new_lat = math.asin(
        math.sin(lat) * math.cos(ang) +
        math.cos(lat) * math.sin(ang) * math.cos(hdg)
    )
    new_lon = lon + math.atan2(
        math.sin(hdg) * math.sin(ang) * math.cos(lat),
        math.cos(ang) - math.sin(lat) * math.sin(new_lat)
    )
    return math.degrees(new_lat), math.degrees(new_lon)


def get_airport(cursor: sqlite3.Cursor, ident: str) -> sqlite3.Row | None:
    return cursor.execute(
        "SELECT * FROM airports WHERE ident = ?", (ident,)
    ).fetchone()


def get_runways(cursor: sqlite3.Cursor, airport_ident: str) -> list[sqlite3.Row]:
    return cursor.execute(
        "SELECT * FROM runways WHERE airport_ident = ?", (airport_ident,)
    ).fetchall()


def make_styles() -> dict:
    airport_style = simplekml.Style()
    airport_style.iconstyle.icon.href = "http://maps.google.com/mapfiles/kml/pushpin/blue-pushpin.png"
    airport_style.iconstyle.scale = 1.2

    threshold_style = simplekml.Style()
    threshold_style.iconstyle.icon.href = "http://maps.google.com/mapfiles/kml/shapes/airports.png"
    threshold_style.iconstyle.scale = 1.0

    disp_style = simplekml.Style()
    disp_style.iconstyle.icon.href = "http://maps.google.com/mapfiles/kml/paddle/ylw-circle.png"
    disp_style.iconstyle.scale = 0.8

    disp_line_style = simplekml.Style()
    disp_line_style.linestyle.color = simplekml.Color.orange
    disp_line_style.linestyle.width = 2

    return {
        "airport": airport_style,
        "threshold": threshold_style,
        "displaced": disp_style,
        "line": disp_line_style,
    }


def build_kml(airport: sqlite3.Row, runways: list[sqlite3.Row]) -> simplekml.Kml:
    kml = simplekml.Kml(name=f"{airport['ident']} — {airport['name']}")
    styles = make_styles()

    pt = kml.newpoint(
        name=f"{airport['ident']} — {airport['name']}",
        coords=[(airport['longitude_deg'], airport['latitude_deg'])]
    )
    pt.style = styles["airport"]
    pt.description = f"Elevation: {airport['elevation_ft']} ft"

    for rwy in runways:
        lat = rwy['latitude_deg']
        lon = rwy['longitude_deg']
        heading = rwy['heading_degT']
        disp_ft = rwy['displaced_threshold_ft'] or 0

        thr = kml.newpoint(
            name=rwy['ident'],
            coords=[(lon, lat)]
        )
        thr.style = styles["threshold"]
        thr.description = (
            f"Heading: {heading}°T\n"
            f"Length: {rwy['length_ft']} ft\n"
            f"Elevation: {rwy['elevation_ft']} ft"
        )

        if disp_ft > 0 and heading is not None:
            disp_lat, disp_lon = project_point(lat, lon, heading, disp_ft)

            disp_pt = kml.newpoint(
                name=f"{rwy['ident']} displaced ({disp_ft} ft)",
                coords=[(disp_lon, disp_lat)]
            )
            disp_pt.style = styles["displaced"]

            line = kml.newlinestring(
                name=f"RWY {rwy['ident']} displaced ({disp_ft} ft)",
                coords=[(lon, lat), (disp_lon, disp_lat)]
            )
            line.style = styles["line"]

    return kml


def get_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a KML file from airport and runway data in an aviation SQLite database."
    )
    parser.add_argument('db', help='Path to aviation SQLite database')
    parser.add_argument('airport_ident', help='Airport identifier (e.g. KSFO)')
    return parser.parse_args()


def main():
    args = get_args()
    airport_ident = args.airport_ident.upper()

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    airport = get_airport(cursor, airport_ident)
    if airport is None:
        print(f"Airport '{airport_ident}' not found in database.", file=sys.stderr)
        sys.exit(1)

    runways = get_runways(cursor, airport_ident)
    conn.close()

    kml = build_kml(airport, runways)

    output_path = f"{airport_ident}.kml"
    kml.save(output_path)
    print(f"Saved {output_path} ({len(runways)} runways)")


if __name__ == '__main__':
    main()
