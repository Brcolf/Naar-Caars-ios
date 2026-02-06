//
//  GeocodingCacheService.swift
//  NaarsCars
//
//  Reverse-geocoding fallback, cache read/write, and cache cleanup for ride cost estimation
//

import Foundation
import CoreLocation
import Supabase

// MARK: - Geocoding Cache Types & Methods

extension RideCostEstimator {
    
    // MARK: - Cache Model Types
    
    struct GeocodingCacheRow: Decodable {
        let multiplier: Double
    }
    
    struct GeocodingCacheUpsert: Encodable {
        let latitude: Double
        let longitude: Double
        let locationKey: String
        let multiplier: Double
        let placemarkData: PlacemarkData?
        
        enum CodingKeys: String, CodingKey {
            case latitude
            case longitude
            case locationKey = "location_key"
            case multiplier
            case placemarkData = "placemark_data"
        }
    }
    
    struct PlacemarkData: Encodable {
        let name: String?
        let thoroughfare: String?
        let subThoroughfare: String?
        let locality: String?
        let subLocality: String?
        let administrativeArea: String?
        let subAdministrativeArea: String?
        let postalCode: String?
        let country: String?
        let isoCountryCode: String?
        let areasOfInterest: [String]?
        let ocean: String?
        let inlandWater: String?
    }
    
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
            multiplier: multiplier,
            placemark: placemark
        )
        
        return multiplier
    }
    
    /// Cleanup old cache entries. Call on app launch or periodically.
    static func cleanupGeocodingCache() async {
        guard await ensureGeocodingCacheAvailable() else { return }
        
        let cutoffDate = Date().addingTimeInterval(-Double(geocodingCacheCleanupDays) * 24 * 60 * 60)
        let cutoffString = isoTimestamp(for: cutoffDate)
        
        do {
            let supabase = await MainActor.run { SupabaseService.shared.client }
            try await supabase
                .from(geocodingCacheTable)
                .delete()
                .lt("created_at", value: cutoffString)
                .execute()
            
            AppLogger.info("rideCost", "Cleaned geocoding cache entries before \(cutoffString)")
        } catch {
            AppLogger.error("rideCost", "Failed to cleanup geocoding cache: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cache Read/Write
    
    static func fetchCachedMultiplier(locationKey: String) async -> Double? {
        guard await ensureGeocodingCacheAvailable() else { return nil }
        
        let cutoffDate = Date().addingTimeInterval(-geocodingCacheTtlHours * 60 * 60)
        let cutoffString = isoTimestamp(for: cutoffDate)
        
        do {
            let supabase = await MainActor.run { SupabaseService.shared.client }
            let response = try await supabase
                .from(geocodingCacheTable)
                .select("multiplier")
                .eq("location_key", value: locationKey)
                .gte("created_at", value: cutoffString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
            
            let rows = try JSONDecoder().decode([GeocodingCacheRow].self, from: response.data)
            if let cached = rows.first {
                return cached.multiplier
            }
            
            AppLogger.info("rideCost", "Cache miss for \(locationKey)")
        } catch {
            if isMissingGeocodingCacheTable(error) {
                geocodingCacheAvailable = false
            }
            AppLogger.warning("rideCost", "Cache read failed for \(locationKey): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    static func upsertGeocodingCache(
        coordinate: CLLocationCoordinate2D,
        locationKey: String,
        multiplier: Double,
        placemark: CLPlacemark
    ) async {
        guard await ensureGeocodingCacheAvailable() else { return }
        
        let payload = GeocodingCacheUpsert(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            locationKey: locationKey,
            multiplier: multiplier,
            placemarkData: placemarkPayload(from: placemark)
        )
        
        do {
            let supabase = await MainActor.run { SupabaseService.shared.client }
            try await supabase
                .from(geocodingCacheTable)
                .upsert(payload, onConflict: "location_key")
                .execute()
            
            AppLogger.info("rideCost", "Cache upserted for \(locationKey)")
        } catch {
            if isMissingGeocodingCacheTable(error) {
                geocodingCacheAvailable = false
            }
            AppLogger.error("rideCost", "Cache write failed for \(locationKey): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cache Availability
    
    static func ensureGeocodingCacheAvailable() async -> Bool {
        if let available = geocodingCacheAvailable {
            return available
        }
        
        do {
            let supabase = await MainActor.run { SupabaseService.shared.client }
            _ = try await supabase
                .from(geocodingCacheTable)
                .select("id")
                .limit(1)
                .execute()
            
            geocodingCacheAvailable = true
            return true
        } catch {
            if isMissingGeocodingCacheTable(error) {
                geocodingCacheAvailable = false
                AppLogger.warning("rideCost", "geocoding_cache table missing. Caching disabled.")
            } else {
                AppLogger.warning("rideCost", "Cache availability check failed: \(error.localizedDescription)")
            }
            
            return false
        }
    }
    
    static func isMissingGeocodingCacheTable(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else { return false }
        if postgrestError.code == "42P01" {
            return true
        }
        let message = postgrestError.message.lowercased()
        return message.contains("geocoding_cache") && message.contains("does not exist")
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
    
    static func placemarkPayload(from placemark: CLPlacemark) -> PlacemarkData {
        PlacemarkData(
            name: placemark.name,
            thoroughfare: placemark.thoroughfare,
            subThoroughfare: placemark.subThoroughfare,
            locality: placemark.locality,
            subLocality: placemark.subLocality,
            administrativeArea: placemark.administrativeArea,
            subAdministrativeArea: placemark.subAdministrativeArea,
            postalCode: placemark.postalCode,
            country: placemark.country,
            isoCountryCode: placemark.isoCountryCode,
            areasOfInterest: placemark.areasOfInterest,
            ocean: placemark.ocean,
            inlandWater: placemark.inlandWater
        )
    }
    
    static func isoTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
