//
//  MapService.swift
//  NaarsCars
//
//  Service for map operations: geocoding, routing, and map annotations
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Models

/// Represents a mappable request (ride or favor)
struct MapRequest: Identifiable, Equatable {
    let id: UUID
    let type: RequestType
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    
    enum RequestType: Equatable {
        case ride
        case favor
        
        var pinColor: Color {
            switch self {
            case .ride: return .blue
            case .favor: return .orange
            }
        }
        
        var iconName: String {
            switch self {
            case .ride: return "car.fill"
            case .favor: return "wrench.fill"
            }
        }
    }
}

/// Route between two points (for rides)
struct MapRoute: Identifiable {
    let id = UUID()
    let pickup: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    var polyline: MKPolyline?
}

enum MapError: LocalizedError {
    case geocodingFailed
    case routeNotFound
    case invalidAddress
    
    var errorDescription: String? {
        switch self {
        case .geocodingFailed:
            return "Could not find location"
        case .routeNotFound:
            return "Could not calculate route"
        case .invalidAddress:
            return "Invalid address"
        }
    }
}

// MARK: - MapService

/// Service for map operations: geocoding, routing, and creating map annotations
@MainActor
final class MapService {
    static let shared = MapService()
    
    private let geocoder = CLGeocoder()
    
    private init() {}
    
    // MARK: - Geocoding
    
    /// Convert address string to coordinates
    /// - Parameter address: Address string to geocode
    /// - Returns: CLLocationCoordinate2D if successful
    /// - Throws: MapError if geocoding fails
    func geocode(address: String) async throws -> CLLocationCoordinate2D {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapError.invalidAddress
        }
        
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            
            guard let location = placemarks.first?.location?.coordinate else {
                throw MapError.geocodingFailed
            }
            
            return location
        } catch {
            throw MapError.geocodingFailed
        }
    }
    
    /// Batch geocode addresses (for map view)
    /// - Parameter addresses: Array of address strings
    /// - Returns: Dictionary mapping address to coordinate (only successful geocodes included)
    func batchGeocode(addresses: [String]) async -> [String: CLLocationCoordinate2D] {
        var results: [String: CLLocationCoordinate2D] = [:]
        
        // Geocode in parallel with rate limiting
        await withTaskGroup(of: (String, CLLocationCoordinate2D?).self) { group in
            for address in addresses {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return (address, nil)
                    }
                    
                    do {
                        let coordinate = try await self.geocode(address: address)
                        return (address, coordinate)
                    } catch {
                        return (address, nil)
                    }
                }
            }
            
            for await (address, coordinate) in group {
                if let coordinate = coordinate {
                    results[address] = coordinate
                }
            }
        }
        
        return results
    }
    
    // MARK: - Routing
    
    /// Calculate route between two points
    /// - Parameters:
    ///   - from: Starting coordinate
    ///   - to: Destination coordinate
    /// - Returns: MKRoute if successful
    /// - Throws: MapError if route calculation fails
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        
        do {
            let response = try await directions.calculate()
            
            guard let route = response.routes.first else {
                throw MapError.routeNotFound
            }
            
            return route
        } catch {
            throw MapError.routeNotFound
        }
    }
    
    // MARK: - Map Annotations
    
    /// Convert rides to map requests (uses pickup location)
    /// - Parameter rides: Array of Ride models
    /// - Returns: Array of MapRequest with coordinates
    func createMapRequests(from rides: [Ride]) async -> [MapRequest] {
        var mapRequests: [MapRequest] = []
        
        // Filter only open rides
        let openRides = rides.filter { $0.status == .open }
        
        // Batch geocode pickup addresses
        let addresses = openRides.map { $0.pickup }
        let coordinates = await batchGeocode(addresses: addresses)
        
        // Create map requests for successfully geocoded rides
        for ride in openRides {
            guard let coordinate = coordinates[ride.pickup] else {
                continue // Skip if geocoding failed
            }
            
            // Use existing dateString extension if localizedShortDate not available
            let dateString: String
            if #available(iOS 15.0, *) {
                dateString = ride.date.formatted(date: .abbreviated, time: .omitted)
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                dateString = formatter.string(from: ride.date)
            }
            
            let mapRequest = MapRequest(
                id: ride.id,
                type: .ride,
                coordinate: coordinate,
                title: "\(ride.pickup) → \(ride.destination)",
                subtitle: dateString
            )
            
            mapRequests.append(mapRequest)
        }
        
        return mapRequests
    }
    
    /// Convert favors to map requests (uses location)
    /// - Parameter favors: Array of Favor models
    /// - Returns: Array of MapRequest with coordinates
    func createMapRequests(from favors: [Favor]) async -> [MapRequest] {
        var mapRequests: [MapRequest] = []
        
        // Filter only open favors
        let openFavors = favors.filter { $0.status == .open }
        
        // Batch geocode locations
        let addresses = openFavors.map { $0.location }
        let coordinates = await batchGeocode(addresses: addresses)
        
        // Create map requests for successfully geocoded favors
        for favor in openFavors {
            guard let coordinate = coordinates[favor.location] else {
                continue // Skip if geocoding failed
            }
            
            let mapRequest = MapRequest(
                id: favor.id,
                type: .favor,
                coordinate: coordinate,
                title: favor.title,
                subtitle: favor.location
            )
            
            mapRequests.append(mapRequest)
        }
        
        return mapRequests
    }
    
    /// Create map requests from both rides and favors
    /// - Parameters:
    ///   - rides: Array of Ride models
    ///   - favors: Array of Favor models
    /// - Returns: Combined array of MapRequest
    func createMapRequests(rides: [Ride], favors: [Favor]) async -> [MapRequest] {
        let rideRequests = await createMapRequests(from: rides)
        let favorRequests = await createMapRequests(from: favors)
        return rideRequests + favorRequests
    }
}

