//
//  LocationService.swift
//  NaarsCars
//
//  Service for location autocomplete using Google Places REST API
//  Uses Google Places API REST endpoints for autocomplete and place details
//

import Foundation
import CoreLocation
import Combine

// MARK: - Models

/// Place prediction from Google Places autocomplete
struct PlacePrediction: Identifiable, Equatable {
    let placeID: String
    let primaryText: String
    let secondaryText: String
    let fullText: String
    
    var id: String { placeID }
}

/// Detailed place information with coordinates
struct PlaceDetails: Equatable {
    let placeID: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
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
        }
    }
}

// MARK: - LocationService

/// Service for location autocomplete and place search
/// Uses Google Places REST API for autocomplete suggestions
@MainActor
final class LocationService: ObservableObject {
    static let shared = LocationService()
    
    @Published var recentLocations: [SavedLocation] = []
    
    private let session = URLSession.shared
    private let autocompleteBaseURL = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
    private let detailsBaseURL = "https://maps.googleapis.com/maps/api/place/details/json"
    
    // Seattle bounds for biasing results (per PRD)
    // Format: lat,lng|lat,lng (SW corner|NE corner)
    private let seattleBounds = "47.4,-122.5|47.8,-122.1"
    
    private init() {
        loadRecentLocations()
    }
    
    // MARK: - Public Methods
    
    /// Search for place predictions using Google Places autocomplete REST API
    /// - Parameter query: Search query string (minimum 2 characters)
    /// - Returns: Array of place predictions
    /// - Throws: LocationError if search fails
    func searchPlaces(query: String) async throws -> [PlacePrediction] {
        guard !query.isEmpty, query.count >= 2 else { return [] }
        
        guard let apiKey = getGooglePlacesAPIKey() else {
            throw LocationError.apiKeyMissing
        }
        
        // Build query parameters
        var components = URLComponents(string: autocompleteBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "input", value: query),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "locationbias", value: "rectangle:\(seattleBounds)"),
            URLQueryItem(name: "types", value: "address|establishment|geocode"),
            URLQueryItem(name: "components", value: "country:us") // Limit to US for Seattle focus
        ]
        
        guard let url = components?.url else {
            throw LocationError.invalidResponse
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw LocationError.networkError("Invalid response status")
            }
            
            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw LocationError.decodingError
            }
            
            guard status == "OK" || status == "ZERO_RESULTS" else {
                throw LocationError.networkError("API error: \(status)")
            }
            
            guard let predictionsArray = json["predictions"] as? [[String: Any]] else {
                return [] // No results
            }
            
            let predictions = predictionsArray.compactMap { predictionDict -> PlacePrediction? in
                guard let placeID = predictionDict["place_id"] as? String else {
                    return nil
                }
                
                let primaryText = predictionDict["structured_formatting"] as? [String: Any]? ?? predictionDict
                let mainText = primaryText?["main_text"] as? String ?? predictionDict["description"] as? String ?? ""
                let secondaryText = primaryText?["secondary_text"] as? String ?? ""
                let description = predictionDict["description"] as? String ?? mainText
                
                return PlacePrediction(
                    placeID: placeID,
                    primaryText: mainText,
                    secondaryText: secondaryText,
                    fullText: description
                )
            }
            
            return predictions
        } catch let error as LocationError {
            throw error
        } catch {
            throw LocationError.networkError(error.localizedDescription)
        }
    }
    
    /// Get full place details including coordinates
    /// - Parameter placeID: Place ID from prediction
    /// - Returns: Place details with coordinates
    /// - Throws: LocationError if fetch fails
    func getPlaceDetails(placeID: String) async throws -> PlaceDetails {
        guard let apiKey = getGooglePlacesAPIKey() else {
            throw LocationError.apiKeyMissing
        }
        
        // Build query parameters for Place Details
        var components = URLComponents(string: detailsBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "place_id", value: placeID),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "fields", value: "name,formatted_address,geometry")
        ]
        
        guard let url = components?.url else {
            throw LocationError.invalidResponse
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw LocationError.networkError("Invalid response status")
            }
            
            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw LocationError.decodingError
            }
            
            guard status == "OK" else {
                if status == "NOT_FOUND" {
                    throw LocationError.notFound
                }
                throw LocationError.networkError("API error: \(status)")
            }
            
            guard let result = json["result"] as? [String: Any] else {
                throw LocationError.decodingError
            }
            
            let name = result["name"] as? String ?? ""
            let address = result["formatted_address"] as? String ?? ""
            
            guard let geometry = result["geometry"] as? [String: Any],
                  let location = geometry["location"] as? [String: Any],
                  let latitude = location["lat"] as? Double,
                  let longitude = location["lng"] as? Double else {
                throw LocationError.decodingError
            }
            
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            
            return PlaceDetails(
                placeID: placeID,
                name: name,
                address: address,
                coordinate: coordinate
            )
        } catch let error as LocationError {
            throw error
        } catch {
            throw LocationError.networkError(error.localizedDescription)
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
    
    /// Get Google Places API key from Secrets
    /// - Returns: API key string if available, nil otherwise
    private func getGooglePlacesAPIKey() -> String? {
        let key = Secrets.googlePlacesAPIKey
        return key.isEmpty ? nil : key
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

