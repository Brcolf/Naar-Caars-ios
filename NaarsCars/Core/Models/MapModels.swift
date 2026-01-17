//
//  MapModels.swift
//  NaarsCars
//
//  Models for map view display
//

import Foundation
import MapKit
import SwiftUI

// MARK: - Map Request Types

/// Type of request for map display
enum MapRequestType: String, CaseIterable {
    case ride
    case favor
    
    var displayName: String {
        switch self {
        case .ride: return "Rides"
        case .favor: return "Favors"
        }
    }
    
    var iconName: String {
        switch self {
        case .ride: return "car.fill"
        case .favor: return "wrench.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .ride: return .blue
        case .favor: return .orange
        }
    }
}

// MARK: - Map Annotation

/// Map annotation for displaying requests on map
struct RequestAnnotation: Identifiable {
    let id: UUID
    let requestId: UUID
    let type: MapRequestType
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
}

extension RequestAnnotation {
    /// Create annotation from MapRequest
    init(from mapRequest: MapRequest) {
        self.id = mapRequest.id
        self.requestId = mapRequest.id
        self.type = mapRequest.type == .ride ? .ride : .favor
        self.coordinate = mapRequest.coordinate
        self.title = mapRequest.title
        self.subtitle = mapRequest.subtitle
    }
}


