//
//  Structs.swift
//  VirtualPAPI
//
//  Created by Marlon Dutra on 11/15/25.
//

struct Airport {
    let ident: String
    let name: String
    let latitude_deg: Double
    let longitude_deg: Double
    let elevation_ft: Double
}

struct Runway {
    let airport_ident: String
    let ident: String
    let length_ft: Double
    let width_ft: Double
    let latitude_deg: Double
    let longitude_deg: Double
    let elevation_ft: Double?
    let heading_degT: Double?
    let displaced_threshold_ft: Double
}
