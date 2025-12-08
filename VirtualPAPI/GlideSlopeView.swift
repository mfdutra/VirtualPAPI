//
//  GlideSlopeView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/21/25.
//

import SwiftUI

struct GlideSlopeView: View {
    @EnvironmentObject var genericLocation: GenericLocation
    @EnvironmentObject var airportSelection: AirportSelection
    @EnvironmentObject var appSettings: AppSettings
    let locationColor: Color

    var body: some View {
        GeometryReader { geometry in
            // Glide slope indicator
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(red: 0.8, green: 0.8, blue: 0.8))
                    .padding(
                        .horizontal,
                        geometry.size.width / 2 - 50
                    )

                // Center line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 100, height: 5)

                // 3rd markers
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 40)
                    .offset(y: geometry.size.height * 0.33333)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 40)
                    .offset(y: geometry.size.height * 0.16666)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 40)
                    .offset(y: geometry.size.height * -0.33333)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 40)
                    .offset(y: geometry.size.height * -0.16666)

                // Smoothed glide path
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
                    .background(locationColor)
                    .rotationEffect(Angle(degrees: 45))
                    .frame(width: 65, height: 65)
                    .opacity(0.9)
                    .offset(
                        y: geometry.size.height
                            * genericLocation.smoothedGsOffset
                    )
                    .animation(
                        .linear(duration: 1),
                        value: genericLocation.smoothedGsOffset
                    )

                // Instantaneous glide path
                if appSettings.showDebugInfo {
                    Rectangle()
                        .stroke(Color.black, lineWidth: 2)
                        .background(.black)
                        .rotationEffect(Angle(degrees: 45))
                        .frame(width: 20, height: 20)
                        .offset(
                            y: geometry.size.height
                                * genericLocation.gsOffset
                        )
                        .animation(
                            .linear(duration: 1),
                            value: genericLocation.gsOffset
                        )
                }

                if genericLocation.locationIsStale {
                    Text("❌ INVALID ❌")
                        .font(.system(size: 60))
                        .bold()
                        .foregroundColor(Color.red)
                }

                // Descent angle
                Text(
                    "GP: \(airportSelection.descentAngle, specifier: "%.1f")°\nTDZE: \(airportSelection.targetElevation ?? 0, specifier: "%.0f")"
                )
                .offset(x: 130)
                .foregroundColor(
                    Color(red: 0.6, green: 0.6, blue: 0.6)
                )

            }
        }
    }
}
