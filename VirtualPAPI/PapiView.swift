//
//  PapiView.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/18/25.
//

import SwiftUI

struct PapiView: View {
    @State private var slider: Double = 0
    @State private var white1: Double = 0
    @State private var white2: Double = 0
    @State private var white3: Double = 0
    @State private var white4: Double = 0
    @EnvironmentObject var genericLocation: GenericLocation
    @EnvironmentObject var airportSelection: AirportSelection

    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Spacer()
                    Circle()
                        .stroke(Color.gray, lineWidth: 10)
                        .fill(
                            Color(
                                red: 1,
                                green: genericLocation.papiColors[0],
                                blue: genericLocation.papiColors[0]
                            )
                        )
                        .animation(
                            .linear(duration: 1),
                            value: genericLocation.papiColors[0]
                        )
                        .frame(width: geometry.size.width / 7)
                        .padding()
                    Circle()
                        .stroke(Color.gray, lineWidth: 10)
                        .fill(
                            Color(
                                red: 1,
                                green: genericLocation.papiColors[1],
                                blue: genericLocation.papiColors[1]
                            )
                        )
                        .animation(
                            .linear(duration: 1),
                            value: genericLocation.papiColors[1]
                        )
                        .frame(width: geometry.size.width / 7)
                        .padding()
                    Circle()
                        .stroke(Color.gray, lineWidth: 10)
                        .fill(
                            Color(
                                red: 1,
                                green: genericLocation.papiColors[2],
                                blue: genericLocation.papiColors[2]
                            )
                        )
                        .animation(
                            .linear(duration: 1),
                            value: genericLocation.papiColors[2]
                        )

                        .frame(width: geometry.size.width / 7)
                        .padding()
                    Circle()
                        .stroke(Color.gray, lineWidth: 10)
                        .fill(
                            Color(
                                red: 1,
                                green: genericLocation.papiColors[3],
                                blue: genericLocation.papiColors[3]
                            )
                        )
                        .animation(
                            .linear(duration: 1),
                            value: genericLocation.papiColors[3]
                        )
                        .frame(width: geometry.size.width / 7)
                        .padding()
                    Spacer()

                }
                Text(
                    "GP: \(airportSelection.descentAngle, specifier: "%.1f")°\nTDZE: \(airportSelection.targetElevation ?? 0, specifier: "%.0f")"
                )
                .foregroundColor(
                    Color(red: 0.6, green: 0.6, blue: 0.6)
                )
                if genericLocation.locationIsStale {
                    Text("❌ INVALID ❌")
                        .font(.system(size: 60))
                        .bold()
                        .foregroundColor(Color.red)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

#Preview {
    PapiView()
}
