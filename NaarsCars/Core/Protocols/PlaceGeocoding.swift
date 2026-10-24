//
//  PlaceGeocoding.swift
//  NaarsCars
//
//  Place geocoding and the one-shot device location behind protocols, so search, the service-area
//  step and their tests never reach MapKit or Core Location directly
//

import Foundation

/// A resolved place: the label shown to the person and its point.
struct GeocodedPlace: Equatable, Sendable {
    let label: String
    let point: GeoPoint
}

/// Whether the app may read the device location ("while using").
enum LocationAccess: Equatable {
    case notDetermined
    /// Denied or restricted: the app never asks again and never nags.
    case denied
    case allowed
}

/// Forward and reverse geocoding of towns, ZIP codes and addresses. Nothing behind this protocol
/// logs a query or a coordinate.
protocol PlaceGeocoding: AnyObject {
    /// A town, neighbourhood or ZIP code for typed text; nil without a request when the text does not
    /// look like one (`PlaceQuery.looksLikeTownOrZIP`), and nil when the place found is street-level,
    /// so a point is never a home.
    func resolveTownOrZIP(_ query: String) async throws -> GeocodedPlace?
    /// The town of a point (the caller passes an already rounded point); the label is the city only.
    func resolveTownOrZIP(at point: GeoPoint) async throws -> GeocodedPlace?
    /// The first place for a full address (a request's pickup or meeting place); the label is the address.
    func place(forAddress address: String) async throws -> GeocodedPlace?
}

/// One device location fix, asked for only when the person taps a control that needs it.
protocol OneShotLocating: AnyObject {
    var access: LocationAccess { get }
    /// One fix; nil on denial, timeout or failure. Never stored and never logged.
    func currentLocation(timeout: TimeInterval) async -> GeoPoint?
}
