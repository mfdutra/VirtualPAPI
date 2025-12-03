#!/usr/bin/env python3
"""
Airplane flight simulator that reads waypoints from CSV and simulates
flight at 120 knots with position updates every second.
"""

import argparse
import csv
import math
import socket
import time


def read_waypoints(filename):
    """Read waypoints from CSV file."""
    waypoints = []
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            waypoints.append({
                'name': row['Waypoint'],
                'lat': float(row['Latitude']),
                'lon': float(row['Longitude']),
                'alt': float(row['Altitude'])
            })
    return waypoints


def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculate great circle distance between two points in nautical miles.
    Uses haversine formula.
    """
    R = 3440.065  # Earth radius in nautical miles

    # Convert to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    # Haversine formula
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * \
        math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.asin(math.sqrt(a))

    return R * c


def calculate_bearing(lat1, lon1, lat2, lon2):
    """
    Calculate initial bearing (heading) from point 1 to point 2.
    Returns bearing in degrees (0-360), where 0 is North, 90 is East, etc.
    """
    # Convert to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lon = math.radians(lon2 - lon1)

    # Calculate bearing
    x = math.sin(delta_lon) * math.cos(lat2_rad)
    y = math.cos(lat1_rad) * math.sin(lat2_rad) - \
        math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(delta_lon)

    bearing_rad = math.atan2(x, y)
    bearing_deg = math.degrees(bearing_rad)

    # Normalize to 0-360
    return (bearing_deg + 360) % 360


def interpolate_position(wp1, wp2, fraction):
    """
    Interpolate position between two waypoints.
    fraction: 0.0 = at wp1, 1.0 = at wp2
    Returns dict with lat, lon, alt.
    """
    # Linear interpolation for latitude and longitude
    lat = wp1['lat'] + (wp2['lat'] - wp1['lat']) * fraction
    lon = wp1['lon'] + (wp2['lon'] - wp1['lon']) * fraction
    alt = wp1['alt'] + (wp2['alt'] - wp1['alt']) * fraction

    return {'lat': lat, 'lon': lon, 'alt': alt}


def simulate_flight(waypoints, speed_knots=120, dest_ip=None):
    """
    Simulate airplane flight through waypoints.

    Args:
        waypoints: List of waypoint dictionaries
        speed_knots: Speed in knots (nautical miles per hour)
        dest_ip: Destination IP address for UDP messages (optional)
    """
    speed_nm_per_sec = speed_knots / 3600.0  # Convert to nm/second
    speed_mps = speed_knots * 0.514444  # Convert knots to meters per second

    # Setup UDP socket if destination IP is provided
    udp_socket = None
    udp_port = 49002
    if dest_ip:
        udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        print(f"Sending UDP messages to {dest_ip}:{udp_port}")
        print()

    current_wp_idx = 0
    distance_along_segment = 0.0

    print(f"Starting flight simulation at {speed_knots} knots")
    print(f"Route: {' -> '.join([wp['name'] for wp in waypoints])}")
    print()
    print(f"{'Time (s)':>8} | {'Waypoint':>10} | {'Latitude':>12} | {'Longitude':>12} | {'Altitude (ft)':>13} | {'Heading':>8}")
    print("-" * 95)

    elapsed_time = 0

    while current_wp_idx < len(waypoints) - 1:
        wp1 = waypoints[current_wp_idx]
        wp2 = waypoints[current_wp_idx + 1]

        # Calculate total distance for this segment
        segment_distance = haversine_distance(
            wp1['lat'], wp1['lon'], wp2['lat'], wp2['lon'])

        # Calculate fraction along this segment
        if segment_distance > 0:
            fraction = distance_along_segment / segment_distance
        else:
            fraction = 1.0

        # Get current position
        pos = interpolate_position(wp1, wp2, fraction)

        # Calculate heading to next waypoint
        heading = calculate_bearing(
            wp1['lat'], wp1['lon'], wp2['lat'], wp2['lon'])

        # Determine which waypoint we're heading towards
        if fraction < 0.5:
            wp_label = f"→ {wp2['name']}"
        else:
            wp_label = f"→ {wp2['name']}"

        # Print current position
        print(
            f"{elapsed_time:8d} | {wp_label:>10} | {pos['lat']:12.8f} | {pos['lon']:12.8f} | {pos['alt']:13.1f} | {heading:8.2f}°")

        # Send UDP message if configured
        if udp_socket:
            alt_meters = pos['alt'] * 0.3048  # Convert feet to meters
            message = f"XGPSSimulator,{pos['lon']:.8f},{pos['lat']:.8f},{alt_meters:.2f},{heading:.2f},{speed_mps:.2f}"
            udp_socket.sendto(message.encode('utf-8'), (dest_ip, udp_port))

        # Update position for next second
        distance_along_segment += speed_nm_per_sec

        # Check if we've reached the next waypoint
        if distance_along_segment >= segment_distance:
            distance_along_segment = distance_along_segment - segment_distance
            current_wp_idx += 1

        elapsed_time += 1
        time.sleep(1)  # Simulate real-time flight

    # Print final waypoint
    final_wp = waypoints[-1]
    prev_wp = waypoints[-2]
    final_heading = calculate_bearing(
        prev_wp['lat'], prev_wp['lon'], final_wp['lat'], final_wp['lon'])
    print(
        f"{elapsed_time:8d} | {final_wp['name']:>10} | {final_wp['lat']:12.8f} | {final_wp['lon']:12.8f} | {final_wp['alt']:13.1f} | {final_heading:8.2f}°")

    # Send final UDP message if configured
    if udp_socket:
        alt_meters = final_wp['alt'] * 0.3048  # Convert feet to meters
        message = f"XGPSSimulator,{final_wp['lon']:.8f},{final_wp['lat']:.8f},{alt_meters:.2f},{final_heading:.2f},{speed_mps:.2f}"
        udp_socket.sendto(message.encode('utf-8'), (dest_ip, udp_port))
        udp_socket.close()

    print()
    print(f"Arrived at {final_wp['name']} - Flight complete!")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Simulate airplane flight through waypoints at specified speed.'
    )
    parser.add_argument(
        'waypoints_file',
        type=str,
        help='CSV file containing waypoints (Waypoint,Latitude,Longitude,Altitude)'
    )
    parser.add_argument(
        '-s', '--speed',
        type=float,
        default=120.0,
        help='Flight speed in knots (default: 120)'
    )
    parser.add_argument(
        '-i', '--ip',
        type=str,
        default=None,
        help='Destination IP address for UDP messages (port 49002)'
    )

    args = parser.parse_args()

    waypoints = read_waypoints(args.waypoints_file)
    simulate_flight(waypoints, speed_knots=args.speed, dest_ip=args.ip)
