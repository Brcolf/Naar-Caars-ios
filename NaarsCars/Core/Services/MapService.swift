//
//  MapService.swift
//  NaarsCars
//
//  Service for map operations: geocoding, routing, and map annotations
//

import Foundation
import MapKit
import CoreLocation
import SwiftUI

// MARK: - Models

/// Represents a mappable request (ride or favor)
struct MapRequest: Identifiable {
    let id: UUID
    let type: RequestType
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    
    enum RequestType {
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

extension MapRequest: Equatable {
    static func == (lhs: MapRequest, rhs: MapRequest) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle
    }
}

extension MapRequest.RequestType: Equatable {
    static func == (lhs: MapRequest.RequestType, rhs: MapRequest.RequestType) -> Bool {
        switch (lhs, rhs) {
        case (.ride, .ride), (.favor, .favor):
            return true
        default:
            return false
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
final class MapService {
    static let shared = MapService()
    
    private let geocoder = CLGeocoder()
    
    private init() {}
    
    // MARK: - Geocoding
    
    /// Default region hint for geocoding (Seattle area)
    private static let seattleRegion = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
        radius: 50000, // 50km radius
        identifier: "Seattle"
    )
    
    /// Convert address string to coordinates
    /// - Parameter address: Address string to geocode
    /// - Returns: CLLocationCoordinate2D if successful
    /// - Throws: MapError if geocoding fails
    func geocode(address: String) async throws -> CLLocationCoordinate2D {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            AppLogger.warning("map", "Empty address")
            throw MapError.invalidAddress
        }
        
        AppLogger.info("map", "Geocoding: '\(trimmedAddress)'")
        
        // Strategy: If it looks like a POI (no numbers at start, or contains "Airport", "Station", etc.), 
        // try MKLocalSearch first as it's much better for these.
        let looksLikePOI = !trimmedAddress.first!.isNumber || 
                          trimmedAddress.localizedCaseInsensitiveContains("Airport") ||
                          trimmedAddress.localizedCaseInsensitiveContains("Station") ||
                          trimmedAddress.localizedCaseInsensitiveContains("Park")
        
        if looksLikePOI {
            AppLogger.info("map", "POI detected, trying MKLocalSearch first")
            if let coordinate = await searchWithMapKit(query: trimmedAddress) {
                AppLogger.info("map", "Success with MKLocalSearch (POI): \(coordinate.latitude), \(coordinate.longitude)")
                return coordinate
            }
        }

        // Attempt 1: Try geocoding with region hint
        do {
            let placemarks = try await geocoder.geocodeAddressString(
                trimmedAddress,
                in: Self.seattleRegion
            )
            
            if let location = placemarks.first?.location?.coordinate {
                AppLogger.info("map", "Success with region hint: \(location.latitude), \(location.longitude)")
                return location
            }
        } catch {
            // Only log if it's not a "not found" error to reduce noise
            if (error as NSError).code != 8 {
                AppLogger.warning("map", "Region hint error: \(error.localizedDescription)")
            }
        }
        
        // Attempt 2: Try without region hint
        do {
            let placemarks = try await geocoder.geocodeAddressString(trimmedAddress)
            
            if let location = placemarks.first?.location?.coordinate {
                AppLogger.info("map", "Success without region hint: \(location.latitude), \(location.longitude)")
                return location
            }
        } catch {
            if (error as NSError).code != 8 {
                AppLogger.warning("map", "Without region hint error: \(error.localizedDescription)")
            }
        }
        
        // Attempt 3: Try with ", WA" appended
        if !trimmedAddress.localizedCaseInsensitiveContains(", wa") {
            let waAddress = "\(trimmedAddress), WA"
            do {
                let placemarks = try await geocoder.geocodeAddressString(waAddress)
                if let location = placemarks.first?.location?.coordinate {
                    AppLogger.info("map", "Success with WA suffix: \(location.latitude), \(location.longitude)")
                    return location
                }
            } catch {}
        }
        
        // Final Attempt: MKLocalSearch fallback if not already tried
        if !looksLikePOI {
            if let coordinate = await searchWithMapKit(query: trimmedAddress) {
                AppLogger.info("map", "Success with MKLocalSearch fallback: \(coordinate.latitude), \(coordinate.longitude)")
                return coordinate
            }
        }
        
        AppLogger.error("map", "All geocoding attempts failed for: '\(trimmedAddress)'")
        throw MapError.geocodingFailed
    }
    
    /// Use MKLocalSearch as a fallback for geocoding (better for POIs like airports)
    private func searchWithMapKit(query: String) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: Self.seattleRegion.center,
            latitudinalMeters: Self.seattleRegion.radius * 2,
            longitudinalMeters: Self.seattleRegion.radius * 2
        )
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            if let item = response.mapItems.first {
                return item.placemark.coordinate
            }
        } catch {
            AppLogger.warning("map", "MKLocalSearch failed: \(error.localizedDescription)")
        }
        
        return nil
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

