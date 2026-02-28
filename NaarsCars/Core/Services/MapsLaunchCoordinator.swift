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
    /// - Returns: URL with percent-encoded query, or nil if destination is missing.
    static func buildGoogleMapsURL(
        origin: CLLocationCoordinate2D?,
        waypoint: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D?
    ) -> URL? {
        guard let dest = destination else { return nil }
        var components = URLComponents(string: googleMapsDirBase)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(dest.latitude),\(dest.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        if let wp = waypoint {
            // Single waypoint: "lat,lng"; multiple would be "lat1,lng1|lat2,lng2"
            items.append(URLQueryItem(name: "waypoints", value: "\(wp.latitude),\(wp.longitude)"))
        }
        if let orig = origin {
            items.append(URLQueryItem(name: "origin", value: "\(orig.latitude),\(orig.longitude)"))
        }
        components?.queryItems = items
        return components?.url
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

        // Prefer coordinates; destination required for route
        let destination: CLLocationCoordinate2D?
        if let d = dropoffCoord {
            destination = d
        } else {
            destination = nil
        }

        guard let url = buildGoogleMapsURL(origin: currentCoord, waypoint: pickupCoord, destination: destination) else {
            AppLogger.warning(logTag, "[RideMapTap] Google Maps: no dropoff coordinate, cannot build URL")
            return
        }

        AppLogger.info(logTag, "[RideMapTap] params origin=\(currentCoord != nil ? "current" : "omit") pickup=\(pickupCoord != nil ? "coord" : "nil") destination=\(destination != nil ? "coord" : "nil")")
        AppLogger.info(logTag, "[RideMapTap] Google Maps URL: \(url.absoluteString)")

        UIApplication.shared.open(url)
    }
}
