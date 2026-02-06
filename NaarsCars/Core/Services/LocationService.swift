//
//  LocationService.swift
//  NaarsCars
//
//  Service for location autocomplete using Apple's MapKit
//  Uses MKLocalSearchCompleter for autocomplete and MKLocalSearch for place details
//

import Foundation
import CoreLocation
import MapKit
internal import Combine

// MARK: - Models

/// Place prediction from location autocomplete (works with both MapKit and Google Places)
struct PlacePrediction: Identifiable, Equatable {
    let placeID: String
    let primaryText: String
    let secondaryText: String
    let fullText: String
    
    var id: String { placeID }
}

/// Detailed place information with coordinates
struct PlaceDetails {
    let placeID: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

extension PlaceDetails: Equatable {
    static func == (lhs: PlaceDetails, rhs: PlaceDetails) -> Bool {
        lhs.placeID == rhs.placeID &&
        lhs.name == rhs.name &&
        lhs.address == rhs.address &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Saved location for recent locations feature
struct SavedLocation: Codable, Identifiable, Equatable {
    let placeID: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    
    var id: String { placeID }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum LocationError: LocalizedError {
    case notFound
    case apiKeyMissing
    case networkError(String)
    case invalidResponse
    case decodingError
    case searchError(String)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Location not found"
        case .apiKeyMissing:
            return "Google Places API key is missing. Please configure in Secrets.swift"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from location service"
        case .decodingError:
            return "Failed to decode location data"
        case .searchError(let message):
            return "Search error: \(message)"
        }
    }
}

// MARK: - LocationService

/// Service for location autocomplete and place search
/// Uses Apple's MapKit (MKLocalSearchCompleter) for autocomplete suggestions
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    @Published var recentLocations: [SavedLocation] = []
    
    // MapKit search completer for autocomplete
    private let searchCompleter = MKLocalSearchCompleter()
    
    // Seattle region for biasing results
    private let seattleRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
        span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
    )
    
    // Continuation for async search results
    private var searchContinuation: CheckedContinuation<[PlacePrediction], Error>?
    
    private override init() {
        super.init()
        // Use 'self' instead of 'LocationService.shared' to avoid circular reference during initialization
        searchCompleter.delegate = self
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        searchCompleter.region = seattleRegion
        loadRecentLocations()
    }
    
    // MARK: - Public Methods (MapKit Implementation)
    
    /// Search for place predictions using MapKit's MKLocalSearchCompleter
    /// - Parameter query: Search query string (minimum 2 characters)
    /// - Returns: Array of place predictions
    /// - Throws: LocationError if search fails
    func searchPlaces(query: String) async throws -> [PlacePrediction] {
        guard !query.isEmpty, query.count >= 2 else { return [] }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Cancel any previous search
            searchCompleter.cancel()
            
            // Store continuation for delegate callback
            searchContinuation = continuation
            
            // Set query fragment to trigger search
            searchCompleter.queryFragment = query
        }
    }
    
    /// Get full place details including coordinates using MKLocalSearch
    /// - Parameter placeID: Place ID from prediction (for MapKit, this is "title, subtitle" format)
    /// - Returns: Place details with coordinates
    /// - Throws: LocationError if fetch fails
    func getPlaceDetails(placeID: String) async throws -> PlaceDetails {
        // For MapKit, placeID is in format "title, subtitle"
        // Extract the title (first part) for the search query
        let searchQuery = placeID.components(separatedBy: ", ").first ?? placeID
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        request.region = seattleRegion
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            guard let mapItem = response.mapItems.first else {
                throw LocationError.notFound
            }
            
            let name = mapItem.name ?? searchQuery
            let address = formatAddress(from: mapItem.placemark)
            let coordinate = mapItem.placemark.coordinate
            
            // Use the original placeID as the stable identifier
            return PlaceDetails(
                placeID: placeID,
                name: name,
                address: address.isEmpty ? placeID : address,
                coordinate: coordinate
            )
        } catch {
            throw LocationError.searchError(error.localizedDescription)
        }
    }
    
    /// Save location to recents (max 10 locations)
    /// - Parameter location: Saved location to add
    func saveRecentLocation(_ location: SavedLocation) {
        recentLocations.removeAll { $0.placeID == location.placeID }
        recentLocations.insert(location, at: 0)
        if recentLocations.count > 10 {
            recentLocations = Array(recentLocations.prefix(10))
        }
        persistRecentLocations()
    }
    
    // MARK: - Private Methods
    
    /// Format address from CLPlacemark
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let streetNumber = placemark.subThoroughfare {
            components.append(streetNumber)
        }
        if let street = placemark.thoroughfare {
            components.append(street)
        }
        if let city = placemark.locality {
            components.append(city)
        }
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        if let zip = placemark.postalCode {
            components.append(zip)
        }
        
        return components.joined(separator: " ")
    }
    
    private func loadRecentLocations() {
        guard let data = UserDefaults.standard.data(forKey: "recent_locations"),
              let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return
        }
        recentLocations = locations
    }
    
    private func persistRecentLocations() {
        guard let data = try? JSONEncoder().encode(recentLocations) else { return }
        UserDefaults.standard.set(data, forKey: "recent_locations")
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            let predictions = completer.results.map { completion in
                PlacePrediction(
                    placeID: completion.title, // Use title as ID for MapKit
                    primaryText: completion.title,
                    secondaryText: completion.subtitle,
                    fullText: "\(completion.title), \(completion.subtitle)"
                )
            }
            
            // Resume continuation with results
            searchContinuation?.resume(returning: predictions)
            searchContinuation = nil
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            searchContinuation?.resume(throwing: LocationError.searchError(error.localizedDescription))
            searchContinuation = nil
        }
    }
}

