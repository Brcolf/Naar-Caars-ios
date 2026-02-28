//
//  RideDirectionsLauncher.swift
//  NaarsCars
//
//  Builds MKMapItem arrays and opens Apple Maps for ride directions (current → pickup → dropoff or fallback).
//

import Foundation
import MapKit
import CoreLocation
import UIKit

/// Builds map items and opens Apple Maps for ride directions.
/// Use `buildMapItems(...)` for unit-testable logic; use `openInMaps(...)` from the view after geocoding.
enum RideDirectionsLauncher {

    private static let logTag = "rides"

    // MARK: - Unit-testable: build map item array

    /// Builds the ordered array of MKMapItem for directions: optionally start (current), then pickup, then dropoff.
    /// - Parameters:
    ///   - pickupCoord: Pickup coordinate (required for multi-stop).
    ///   - dropoffCoord: Dropoff coordinate (required for multi-stop).
    ///   - currentCoord: If non-nil, used as first stop (start); otherwise result is [pickup, dropoff].
    ///   - pickupName: Name for the pickup map item.
    ///   - dropoffName: Name for the dropoff map item.
    /// - Returns: Non-empty array: either [current, pickup, dropoff] or [pickup, dropoff]. Returns [] if pickup or dropoff is nil.
    static func buildMapItems(
        pickupCoord: CLLocationCoordinate2D?,
        dropoffCoord: CLLocationCoordinate2D?,
        currentCoord: CLLocationCoordinate2D?,
        pickupName: String,
        dropoffName: String
    ) -> [MKMapItem] {
        guard let pickupCoord = pickupCoord, let dropoffCoord = dropoffCoord else {
            return []
        }
        let pickupItem = MKMapItem(placemark: MKPlacemark(coordinate: pickupCoord))
        pickupItem.name = pickupName
        let dropoffItem = MKMapItem(placemark: MKPlacemark(coordinate: dropoffCoord))
        dropoffItem.name = dropoffName

        if let currentCoord = currentCoord {
            let startItem = MKMapItem(placemark: MKPlacemark(coordinate: currentCoord))
            startItem.name = "Current Location"
            return [startItem, pickupItem, dropoffItem]
        }
        return [pickupItem, dropoffItem]
    }

    // MARK: - Open Maps

    /// Opens Apple Maps with the given map items in driving directions mode.
    static func openInMaps(mapItems: [MKMapItem]) {
        guard !mapItems.isEmpty else { return }
        let launchOptions: [String: Any] = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        MKMapItem.openMaps(with: mapItems, launchOptions: launchOptions)
    }

    /// Logs and opens Apple Maps for a ride using the given coordinates. Use after geocoding pickup/destination.
    /// If coords are missing, falls back to opening Maps with address query URL.
    static func openInMaps(
        rideId: UUID,
        pickupCoord: CLLocationCoordinate2D?,
        dropoffCoord: CLLocationCoordinate2D?,
        currentCoord: CLLocationCoordinate2D?,
        pickupAddress: String,
        dropoffAddress: String
    ) {
        AppLogger.info(logTag, "[RideMapTap] hasPickupCoord=\(pickupCoord != nil) hasDropoffCoord=\(dropoffCoord != nil)")

        let items = buildMapItems(
            pickupCoord: pickupCoord,
            dropoffCoord: dropoffCoord,
            currentCoord: currentCoord,
            pickupName: "Pickup: \(pickupAddress)",
            dropoffName: "Dropoff: \(dropoffAddress)"
        )

        if !items.isEmpty {
            if currentCoord != nil {
                AppLogger.info(logTag, "[RideMapTap] opening Maps with waypoint: current -> pickup -> dropoff")
            } else {
                AppLogger.info(logTag, "[RideMapTap] opening Maps fallback: pickup -> dropoff (reason=timeout/denied/noFix)")
            }
            openInMaps(mapItems: items)
            return
        }

        // Fallback: open with address query (directions)
        AppLogger.warning(logTag, "[RideMapTap] no coords; opening Maps with address query")
        let saddr = pickupAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pickupAddress
        let daddr = dropoffAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dropoffAddress
        if let url = URL(string: "https://maps.apple.com/?saddr=\(saddr)&daddr=\(daddr)") {
            UIApplication.shared.open(url)
        }
    }
}
