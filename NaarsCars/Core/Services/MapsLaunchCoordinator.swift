//
//  MapsLaunchCoordinator.swift
//  NaarsCars
//
//  Coordinates opening ride directions in Apple Maps or Google Maps (app or web).
//

import Foundation
import MapKit
import CoreLocation
import UIKit

/// Preferred maps app for directions.
enum PreferredMapsApp: String {
    case apple = "apple"
    case google = "google"
}

/// Builds URLs and opens Apple Maps or Google Maps for ride directions.
enum MapsLaunchCoordinator {

    private static let logTag = "rides"
    private static let googleMapsDirBase = "https://www.google.com/maps/dir/"

    // MARK: - URL building

    /// Builds a maps URL whose query values are fully escaped. `URLQueryItem` escapes "&" and
    /// "=", which `.urlQueryAllowed` leaves alone: "5th Ave & Pine St" reached Maps as "5th Ave ".
    /// "+" is escaped by hand, because URLComponents keeps it and map services read it as a space.
    static func makeURL(base: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = queryItems
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Percent-encodes text for use as one query value in a URL assembled as a string.
    /// Escapes "&", "+" and "=" as well as everything `.urlQueryAllowed` already escapes.
    static func escapedQueryValue(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - Apple Maps

    /// Opens Apple Maps with current → pickup → dropoff when current is available, else pickup → dropoff.
    static func openAppleMaps(
        rideId: UUID,
        pickupCoord: CLLocationCoordinate2D?,
        dropoffCoord: CLLocationCoordinate2D?,
        currentCoord: CLLocationCoordinate2D?,
        pickupAddress: String,
        dropoffAddress: String
    ) {
        AppLogger.info(logTag, "[RideMapTap] chosenProvider=apple")
        RideDirectionsLauncher.openInMaps(
            rideId: rideId,
            pickupCoord: pickupCoord,
            dropoffCoord: dropoffCoord,
            currentCoord: currentCoord,
            pickupAddress: pickupAddress,
            dropoffAddress: dropoffAddress
        )
    }

    // MARK: - Google Maps URL builder (universal URL; waypoints supported)

    /// Builds the universal Google Maps directions URL (api=1) so waypoints are respected.
    /// - Parameters:
    ///   - origin: User current location (lat,lng); if nil, origin is omitted and Google uses current location.
    ///   - waypoint: Pickup (lat,lng); multiple waypoints use "lat1,lng1|lat2,lng2".
    ///   - destination: Dropoff (lat,lng).
    ///   - waypointAddress: Pickup address text, used when `waypoint` is nil (geocoding failed).
    ///   - destinationAddress: Dropoff address text, used when `destination` is nil. Google resolves the text itself.
    /// - Returns: URL with percent-encoded query, or nil if there is neither a destination coordinate nor address text.
    static func buildGoogleMapsURL(
        origin: CLLocationCoordinate2D?,
        waypoint: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D?,
        waypointAddress: String? = nil,
        destinationAddress: String? = nil
    ) -> URL? {
        guard let destinationValue = stopValue(coordinate: destination, address: destinationAddress) else {
            return nil
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destinationValue),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        // Single waypoint: "lat,lng"; multiple would be "lat1,lng1|lat2,lng2". "|" separates
        // waypoints, so it cannot stay inside an address.
        if let waypointValue = stopValue(
            coordinate: waypoint,
            address: waypointAddress?.replacingOccurrences(of: "|", with: " ")
        ) {
            items.append(URLQueryItem(name: "waypoints", value: waypointValue))
        }
        if let orig = origin {
            items.append(URLQueryItem(name: "origin", value: "\(orig.latitude),\(orig.longitude)"))
        }
        return makeURL(base: googleMapsDirBase, queryItems: items)
    }

    /// A stop for the Google Maps URL: "lat,lng" when the address was geocoded, else its text.
    private static func stopValue(coordinate: CLLocationCoordinate2D?, address: String?) -> String? {
        if let coordinate = coordinate {
            return "\(coordinate.latitude),\(coordinate.longitude)"
        }
        let text = address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    // MARK: - Google Maps open

    /// Opens Google Maps via universal URL (current → pickup → dropoff). Waypoints work in this format.
    static func openGoogleMaps(
        rideId: UUID,
        pickupCoord: CLLocationCoordinate2D?,
        dropoffCoord: CLLocationCoordinate2D?,
        currentCoord: CLLocationCoordinate2D?,
        pickupAddress: String,
        dropoffAddress: String
    ) {
        AppLogger.info(logTag, "[RideMapTap] chosenProvider=google")

        // Prefer coordinates. When an address could not be geocoded its text is sent instead,
        // the way the Apple Maps path falls back; this used to return without opening anything.
        guard let url = buildGoogleMapsURL(
            origin: currentCoord,
            waypoint: pickupCoord,
            destination: dropoffCoord,
            waypointAddress: pickupAddress,
            destinationAddress: dropoffAddress
        ) else {
            AppLogger.warning(logTag, "[RideMapTap] Google Maps: no dropoff coordinate or address, cannot build URL")
            return
        }

        AppLogger.info(logTag, "[RideMapTap] params origin=\(currentCoord != nil ? "current" : "omit") pickup=\(pickupCoord != nil ? "coord" : "address") destination=\(dropoffCoord != nil ? "coord" : "address")")
        AppLogger.info(logTag, "[RideMapTap] Google Maps URL: \(url.absoluteString)")

        UIApplication.shared.open(url)
    }
}
