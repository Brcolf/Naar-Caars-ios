//
//  PlaceGeocoder.swift
//  NaarsCars
//
//  MapKit geocoding (MKGeocodingRequest / MKReverseGeocodingRequest, which replace the deprecated
//  CLGeocoder), the one-shot device location, and the rules that tell a town or ZIP code from a street
//  address. Nothing here logs a query, an address or a coordinate.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - PlaceQuery

/// Pure rules on typed place text and geocoded addresses. Input is trimmed first.
enum PlaceQuery {
    private static let zipPattern = "^[0-9]{5}(-[0-9]{4})?$"
    /// The same house-number pattern the server applies to an area name (`20261021_0021`).
    private static let houseNumberPattern = "(^|\\s)[0-9]{1,6}\\s+\\p{L}"

    /// A US ZIP code, five digits with an optional "-1234".
    static func isZIP(_ text: String) -> Bool {
        matches(trimmed(text), zipPattern)
    }

    /// A number of one to six digits followed by a word, as in "5412 Probe Ln" ("Pier 66" and a lone ZIP are not).
    static func hasHouseNumber(_ text: String) -> Bool {
        matches(trimmed(text), houseNumberPattern)
    }

    /// A ZIP code, or at least three characters with a letter and no house number.
    static func looksLikeTownOrZIP(_ text: String) -> Bool {
        let value = trimmed(text)
        if isZIP(value) { return true }
        return value.count >= 3 && value.contains(where: \.isLetter) && !hasHouseNumber(value)
    }

    /// Whether a geocoded item's single-line address is a street address (a home or a building).
    static func isStreetLevel(fullAddress: String?) -> Bool {
        guard let fullAddress else { return false }
        return hasHouseNumber(fullAddress)
    }

    /// The label of a resolved place, cut to `Constants.Community.areaNameMaxLength`:
    /// a ZIP query is "<ZIP> · <city>" (the ZIP alone without a city); a place that is the city, or no
    /// place, is the city; a place in a city is "<place>, <city>"; a place with no city is the place;
    /// nothing is nil. A place name that is itself a ZIP code is ignored, so a label never starts with a
    /// postal code followed by a word (the server refuses that as a house number).
    static func label(placeName: String?, cityName: String?, query: String) -> String? {
        let query = trimmed(query)
        let place = nonEmpty(placeName).flatMap { isZIP($0) ? nil : $0 }
        let city = nonEmpty(cityName)
        let label: String?
        if isZIP(query) {
            label = city.map { "\(query) · \($0)" } ?? query
        } else if let place, let city, place.caseInsensitiveCompare(city) != .orderedSame {
            label = "\(place), \(city)"
        } else {
            label = city ?? place
        }
        return label.map { String($0.prefix(Constants.Community.areaNameMaxLength)) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - PlaceGeocoder

/// MapKit geocoding. Each call makes its own request object.
final class PlaceGeocoder: PlaceGeocoding {
    static let shared = PlaceGeocoder()

    private init() {}

    func resolveTownOrZIP(_ query: String) async throws -> GeocodedPlace? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlaceQuery.looksLikeTownOrZIP(text),
              let item = try await firstForwardItem(for: text, in: nil) else { return nil }
        // A street-level answer to a town query is refused, so a centre is never a house (spec 4.2).
        guard !PlaceQuery.isStreetLevel(fullAddress: Self.singleLineAddress(of: item)),
              let label = PlaceQuery.label(
                placeName: item.name,
                cityName: item.addressRepresentations?.cityName,
                query: text
              ) else { return nil }
        return GeocodedPlace(label: label, point: GeoPoint(item.location.coordinate))
    }

    func resolveTownOrZIP(at point: GeoPoint) async throws -> GeocodedPlace? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let items = try await withTaskCancellationHandler {
            try await request.mapItems
        } onCancel: {
            request.cancel()
        }
        guard let city = items.first?.addressRepresentations?.cityName,
              let label = PlaceQuery.label(placeName: nil, cityName: city, query: "") else { return nil }
        return GeocodedPlace(label: label, point: point)
    }

    func place(forAddress address: String) async throws -> GeocodedPlace? {
        try await place(forAddress: address, in: nil)
    }

    /// The first place for an address; `region` bounds the request (`MKGeocodingRequest.region`).
    func place(forAddress address: String, in region: MKCoordinateRegion?) async throws -> GeocodedPlace? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = try await firstForwardItem(for: text, in: region) else { return nil }
        return GeocodedPlace(label: text, point: GeoPoint(item.location.coordinate))
    }

    private func firstForwardItem(for text: String, in region: MKCoordinateRegion?) async throws -> MKMapItem? {
        guard let request = MKGeocodingRequest(addressString: text) else { return nil }
        if let region { request.region = region }
        let items = try await withTaskCancellationHandler {
            try await request.mapItems
        } onCancel: {
            request.cancel()
        }
        return items.first
    }

    /// The item's address on one line without the country, where a house number would show.
    private static func singleLineAddress(of item: MKMapItem) -> String? {
        item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.shortAddress
    }
}

private extension GeoPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

// MARK: - DeviceLocator

/// One "while using" location fix through `CurrentLocationProvider`, asked for only on a tap.
/// The fix is returned to the caller and never stored or logged.
final class DeviceLocator: OneShotLocating {
    /// Reads the authorization status only; it has no delegate and requests nothing.
    private let statusManager = CLLocationManager()

    var access: LocationAccess {
        switch statusManager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .allowed
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func currentLocation(timeout: TimeInterval) async -> GeoPoint? {
        guard access != .denied else { return nil }
        // The provider's location manager is created on the main thread so its delegate is called.
        let provider = await MainActor.run { CurrentLocationProvider() }
        let coordinate: CLLocationCoordinate2D? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    provider.requestCurrentLocation(timeout: timeout) { continuation.resume(returning: $0) }
                }
            }
        } onCancel: {
            DispatchQueue.main.async { provider.stop() }
        }
        return coordinate.map { GeoPoint($0) }
    }
}

// MARK: - Preview stand-ins

#if DEBUG
/// Fixed answers and no network, for `#Preview`s (inside `#if DEBUG`) of the search and area screens.
final class PreviewPlaceGeocoder: PlaceGeocoding {
    static let seattle = GeocodedPlace(label: "Seattle", point: GeoPoint(latitude: 47.606, longitude: -122.332))

    private let result: GeocodedPlace?

    init(result: GeocodedPlace? = PreviewPlaceGeocoder.seattle) {
        self.result = result
    }

    func resolveTownOrZIP(_ query: String) async throws -> GeocodedPlace? {
        PlaceQuery.looksLikeTownOrZIP(query) ? result : nil
    }

    func resolveTownOrZIP(at point: GeoPoint) async throws -> GeocodedPlace? {
        result.map { GeocodedPlace(label: $0.label, point: point) }
    }

    func place(forAddress address: String) async throws -> GeocodedPlace? {
        result.map { GeocodedPlace(label: address, point: $0.point) }
    }
}

/// A fixed access state and fix, for `#Preview`s (inside `#if DEBUG`).
final class PreviewLocator: OneShotLocating {
    let access: LocationAccess
    private let location: GeoPoint?

    init(access: LocationAccess = .allowed, location: GeoPoint? = PreviewPlaceGeocoder.seattle.point) {
        self.access = access
        self.location = location
    }

    func currentLocation(timeout: TimeInterval) async -> GeoPoint? {
        access == .allowed ? location : nil
    }
}
#endif
