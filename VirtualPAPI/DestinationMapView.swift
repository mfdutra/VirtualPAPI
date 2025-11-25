//
//  DestinationMapView.swift
//  VirtualPAPI
//
//  Created by Claude on 11/25/25.
//

import MapKit
import SwiftUI

struct DestinationMapView: View {
    @EnvironmentObject var genericLocation: GenericLocation

    var body: some View {
        if let targetLat = genericLocation.airportSelection?.targetLatitude,
            let targetLon = genericLocation.airportSelection?.targetLongitude
        {
            Map {
                Annotation(
                    "Aiming point",
                    coordinate: CLLocationCoordinate2D(
                        latitude: targetLat,
                        longitude: targetLon
                    )
                ) {
                    Image(systemName: "airplane.arrival")
                        .foregroundColor(.red)
                        .font(.title)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapCameraKeyframeAnimator(trigger: targetLat) {
                camera in
                KeyframeTrack(\MapCamera.centerCoordinate) {
                    CubicKeyframe(
                        CLLocationCoordinate2D(
                            latitude: targetLat,
                            longitude: targetLon
                        ),
                        duration: 0.3
                    )
                }
                KeyframeTrack(\MapCamera.distance) {
                    CubicKeyframe(500, duration: 0.3)
                }
            }
            .navigationTitle("Destination Map")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                "No Destination Selected",
                systemImage: "map",
                description: Text(
                    "Select an airport and runway to view the destination map"
                )
            )
            .navigationTitle("Destination Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
