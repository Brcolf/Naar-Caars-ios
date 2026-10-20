//
//  GeocodingCacheService.swift
//  NaarsCars
//
//  Reverse-geocoding fallback and the place-multiplier cache (read and written only through
//  get_geocoding_multiplier / put_geocoding_multiplier) for ride cost estimation
//

import Foundation
import CoreLocation
import Supabase

// MARK: - RPC parameters (explicit keys)

/// `get_geocoding_multiplier(p_location_key text) -> numeric` (20261019_0050 block 1).
/// Answers the cached multiplier for an active account and a fresh, well-formed key; null otherwise.
private struct GeocodingLookupParams: Encodable, Sendable {
    let locationKey: String

    private enum CodingKeys: String, CodingKey { case p_location_key }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(locationKey, forKey: .p_location_key)
    }
}

/// `put_geocoding_multiplier(p_location_key text, p_latitude numeric, p_longitude numeric, p_multiplier numeric)
/// -> boolean` (20261019_0050 block 2). No placemark data is sent; the server answers false on any refusal.
private struct GeocodingWriteParams: Encodable, Sendable {
    let locationKey: String
    let latitude: Double
    let longitude: Double
    let multiplier: Double

    private enum CodingKeys: String, CodingKey { case p_location_key, p_latitude, p_longitude, p_multiplier }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(locationKey, forKey: .p_location_key)
        try c.encode(latitude, forKey: .p_latitude)
        try c.encode(longitude, forKey: .p_longitude)
        try c.encode(multiplier, forKey: .p_multiplier)
    }
}

// MARK: - Geocoding Cache Methods

extension RideCostEstimator {
    
    // MARK: - Reverse Geocoding Fallback
    
    /// Reverse geocoding fallback when no premium zone matches.
    static func getReverseGeocodedMultiplier(coordinate: CLLocationCoordinate2D) async -> Double {
        let locationKey = cacheKey(for: coordinate)
        
        if let cachedMultiplier = await fetchCachedMultiplier(locationKey: locationKey) {
            AppLogger.info("rideCost", "Cache hit for \(locationKey): \(cachedMultiplier)")
            return cachedMultiplier
        }
        
        guard let placemark = await reverseGeocodePlacemark(for: coordinate) else {
            AppLogger.warning("rideCost", "Reverse geocoding failed for \(locationKey). Defaulting to 1.0.")
            return 1.0
        }
        
        let multiplier = placemarkMultiplier(for: placemark)
        AppLogger.info("rideCost", "Reverse geocoded multiplier: \(multiplier) (\(locationKey))")
        
        await upsertGeocodingCache(
            coordinate: coordinate,
            locationKey: locationKey,
            multiplier: multiplier
        )
        
        return multiplier
    }
    
    // MARK: - Cache Read/Write (definer RPCs; the client never reads or writes the cache table)
    
    /// The cached multiplier for `locationKey`, or nil on a miss, a refusal or an error.
    /// Freshness (24 hours) and the active-account check are decided by the server.
    static func fetchCachedMultiplier(locationKey: String) async -> Double? {
        guard geocodingCacheAvailable != false else { return nil }
        
        do {
            let supabase = await MainActor.run { SupabaseService.shared.client }
            let response = try await supabase
                .rpc("get_geocoding_multiplier", params: GeocodingLookupParams(locationKey: locationKey))
                .execute()
            geocodingCacheAvailable = true
            
            if let cached = try JSONDecoder().decode(Double?.self, from: response.data) {
                return cached
            }
            
            AppLogger.info("rideCost", "Cache miss for \(locationKey)")
        } catch {
            if isMissingGeocodingFunction(error) {
                geocodingCacheAvailable = false
                AppLogger.warning("rideCost", "Geocoding lookup function missing. Caching disabled for this session.")
            } else {
                AppLogger.warning("rideCost", "Cache read failed for \(locationKey): \(error.localizedDescription)")
            }
        }
        
        return nil
    }
    
    /// Stores the multiplier computed on the device for `locationKey`. Best effort: a refusal
    /// (`false`) is logged and ignored.
    static func upsertGeocodingCache(
        coordinate: CLLocationCoordinate2D,
        locationKey: String,
        multiplier: Double
    ) async {
        guard geocodingCacheAvailable != false else { return }
        
        let params = GeocodingWriteParams(
            locationKey: locationKey,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            multiplier: multiplier
        )
        
        do {
            let supabase = await MainActor.run { SupabaseService.shared.client }
            let response = try await supabase
                .rpc("put_geocoding_multiplier", params: params)
                .execute()
            geocodingCacheAvailable = true
            
            let stored = (try? JSONDecoder().decode(Bool?.self, from: response.data)) ?? nil
            if stored == true {
                AppLogger.info("rideCost", "Cache written for \(locationKey)")
            } else {
                AppLogger.info("rideCost", "Cache write not accepted for \(locationKey)")
            }
        } catch {
            if isMissingGeocodingFunction(error) {
                geocodingCacheAvailable = false
                AppLogger.warning("rideCost", "Geocoding write function missing. Caching disabled for this session.")
            } else {
                AppLogger.warning("rideCost", "Cache write failed for \(locationKey): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Cache Availability
    
    /// True when PostgREST could not find the function (`PGRST202`) or Postgres reports an
    /// undefined function (`42883`): the lookup is then turned off for the session.
    static func isMissingGeocodingFunction(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else { return false }
        return postgrestError.code == "PGRST202" || postgrestError.code == "42883"
    }
    
    // MARK: - Geocoding Helpers
    
    static func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let format = "%.\(cacheKeyPrecision)f"
        let locale = Locale(identifier: "en_US_POSIX")
        let latString = String(format: format, locale: locale, coordinate.latitude)
        let lonString = String(format: format, locale: locale, coordinate.longitude)
        return "\(latString)_\(lonString)"
    }
    
    static func reverseGeocodePlacemark(for coordinate: CLLocationCoordinate2D) async -> CLPlacemark? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let result = await withTimeout(seconds: reverseGeocodeTimeoutSeconds) {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                return placemark
            }
            throw NSError(
                domain: "RideCostEstimator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No placemark returned"]
            )
        }
        
        if result == nil {
            AppLogger.warning("rideCost", "Reverse geocoding timed out or returned no placemark.")
        }
        
        return result
    }
    
    static func placemarkMultiplier(for placemark: CLPlacemark) -> Double {
        if isAirportPlacemark(placemark) {
            return 1.5
        }
        
        let normalizedText = normalizedPlacemarkText(for: placemark)
        if normalizedText.contains("queen anne") {
            return 1.2
        }
        if normalizedText.contains("green lake") {
            return 1.1
        }
        if normalizedText.contains("georgetown") {
            return 1.1
        }
        if normalizedText.contains("west seattle") {
            return 1.1
        }
        if normalizedText.contains("magnolia") {
            return 1.1
        }
        
        if let locality = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locality.isEmpty {
            let localityLower = locality.lowercased()
            if localityLower == "bellevue" || localityLower == "redmond" {
                return isBusinessDistrict(placemark) ? 1.2 : 1.0
            }
            
            let suburbanCities = [
                "kirkland",
                "renton",
                "kent",
                "federal way",
                "tacoma",
                "bellevue",
                "redmond"
            ]
            
            if suburbanCities.contains(localityLower) {
                return 1.0
            }
        } else {
            return 0.9
        }
        
        return 1.0
    }
    
    static func normalizedPlacemarkText(for placemark: CLPlacemark) -> String {
        [
            placemark.name,
            placemark.subLocality,
            placemark.locality,
            placemark.thoroughfare,
            placemark.subThoroughfare,
            placemark.administrativeArea
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }
    
    static func isAirportPlacemark(_ placemark: CLPlacemark) -> Bool {
        let name = placemark.name?.lowercased() ?? ""
        if name.contains("airport") {
            return true
        }
        
        let areas = placemark.areasOfInterest ?? []
        return areas.contains { $0.lowercased().contains("airport") }
    }
    
    static func isBusinessDistrict(_ placemark: CLPlacemark) -> Bool {
        let hints = [
            placemark.name,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.areasOfInterest?.joined(separator: " ")
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        
        let keywords = [
            "downtown",
            "city center",
            "business district",
            "main st",
            "main street",
            "town center",
            "square",
            "corporate",
            "office",
            "overlake",
            "bellevue square",
            "redmond town center",
            "microsoft"
        ]
        
        return keywords.contains { hints.contains($0) }
    }
}
