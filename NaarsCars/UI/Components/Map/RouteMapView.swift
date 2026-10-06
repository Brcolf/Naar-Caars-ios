//
//  RouteMapView.swift
//  NaarsCars
//
//  Compact map view showing route between two points
//

import SwiftUI
import MapKit

/// Loading state for map view
enum MapLoadingState: Equatable {
    case loading
    case loaded
    case error(String)
    
    static func == (lhs: MapLoadingState, rhs: MapLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.loaded, .loaded): return true
        case (.error(let lhsMsg), .error(let rhsMsg)): return lhsMsg == rhsMsg
        default: return false
        }
    }
}

/// Compact map view showing a route between pickup and destination
struct RouteMapView: View {
    let pickup: String
    let destination: String
    /// Reports whether a route exists between the two addresses: `true` once it is drawn,
    /// `false` when an address cannot be found or no route connects them. Not called for
    /// transient failures. The ride screen hides its savings estimate for a ride with no route.
    var onRouteResolved: ((Bool) -> Void)?
    @State private var pickupCoordinate: CLLocationCoordinate2D?
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var cameraPosition: MapCameraPosition
    @State private var loadingState: MapLoadingState = .loading
    @State private var retryCount = 0
    /// The addresses the drawn route belongs to; nil until a route has been drawn.
    @State private var drawnPickup: String?
    @State private var drawnDestination: String?
    /// True when the last failure was a connection or service problem, not a missing route.
    @State private var lastFailureWasTransient = false

    // Default Seattle center
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    
    // Maximum retry attempts
    private static let maxRetries = 2
    
    init(pickup: String, destination: String, onRouteResolved: ((Bool) -> Void)? = nil) {
        self.pickup = pickup
        self.destination = destination
        self.onRouteResolved = onRouteResolved

        // Initial camera position (will be updated when coordinates are available)
        let initialRegion = MKCoordinateRegion(
            center: Self.defaultCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        _cameraPosition = State(initialValue: .region(initialRegion))
    }
    
    var body: some View {
        contentView
            // Keyed on the two addresses as well as the retry count. The task used to re-run
            // only on Retry, so after the poster edited the pickup or destination the card
            // showed the new addresses above the old route. It also runs again each time the
            // view reappears; `loadRoute()` returns at once when this pair is already drawn.
            .task(id: RouteLoadKey(pickup: pickup, destination: destination, attempt: retryCount)) {
                await loadRoute()
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch loadingState {
        case .loading:
            loadingView
            
        case .loaded:
            if let pickupCoord = pickupCoordinate,
               let destCoord = destinationCoordinate {
                mapView(pickupCoord: pickupCoord, destCoord: destCoord)
            } else {
                errorView(message: "route_unavailable".localized)
            }
            
        case .error(let message):
            errorView(message: message)
        }
    }
    
    private var loadingView: some View {
        ZStack {
            Color(.systemGray5)
            VStack(spacing: 8) {
                ProgressView()
                Text("route_loading".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 200)
        .cornerRadius(Constants.Radius.sm)
    }
    
    private func mapView(pickupCoord: CLLocationCoordinate2D, destCoord: CLLocationCoordinate2D) -> some View {
        Map(position: $cameraPosition) {
            // Route polyline (drawn first so it appears below markers)
            if let route = route {
                MapPolyline(route.polyline)
                    .stroke(Color.rideAccent, lineWidth: 4)
            }
            
            // Pickup marker
            Annotation("route_annotation_pickup".localized, coordinate: pickupCoord) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .floatingShadow()
                    Image(systemName: "circle.fill")
                        .foregroundColor(.naarsSuccess)
                        .font(.naarsFootnote)
                }
            }
            
            // Destination marker
            Annotation("route_annotation_destination".localized, coordinate: destCoord) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .floatingShadow()
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.rideAccent)
                        .font(.naarsTitle3)
                }
            }
        }
        .frame(height: 200)
        .cornerRadius(Constants.Radius.sm)
        .allowsHitTesting(false) // Let taps pass through to the parent container
    }
    
    @ViewBuilder
    private func errorView(message: String) -> some View {
        ZStack {
            Color(.systemGray5)
            VStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(message)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // A connection or service failure can always be retried. The cap applies only
                // when the addresses themselves could not be found or routed.
                if lastFailureWasTransient || retryCount < Self.maxRetries {
                    Button {
                        // The task is keyed on retryCount, so this starts a new attempt.
                        retryCount += 1
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("common_retry".localized)
                        }
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding()
        }
        // At least as tall as the map, and taller when large text needs the room.
        .frame(minHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
        .cornerRadius(Constants.Radius.sm)
    }

    private func loadRoute() async {
        // Returning to the screen re-runs the task. The route for this pair is already on
        // screen, so do not flash "Loading route..." or repeat the lookups (Apple rate-limits them).
        if loadingState == .loaded, drawnPickup == pickup, drawnDestination == destination {
            return
        }

        // Reset to loading state at the start
        loadingState = .loading

        do {
            // Check for cancellation before starting
            try Task.checkCancellation()
            
            // Geocode both addresses sequentially to avoid CLGeocoder concurrency issues
            let pickupCoord = try await MapService.shared.geocode(address: pickup)
            
            // Check for cancellation between operations
            try Task.checkCancellation()
            
            let destCoord = try await MapService.shared.geocode(address: destination)
            
            try Task.checkCancellation()
            
            // Calculate route
            let calculatedRoute = try await MapService.shared.calculateRoute(from: pickupCoord, to: destCoord)
            
            try Task.checkCancellation()
            
            // Update state
            self.pickupCoordinate = pickupCoord
            self.destinationCoordinate = destCoord
            self.route = calculatedRoute
            
            // Update camera position to fit the entire route with padding
            let routeRect = calculatedRoute.polyline.boundingMapRect
            
            // Safely calculate padded rect (ensure positive dimensions)
            let paddingX = max(routeRect.size.width * 0.2, 1000)  // Minimum padding
            let paddingY = max(routeRect.size.height * 0.2, 1000)
            let paddedRect = routeRect.insetBy(dx: -paddingX, dy: -paddingY)
            
            // Use region instead of rect for more reliable rendering
            let region = MKCoordinateRegion(paddedRect)
            self.cameraPosition = .region(region)

            self.drawnPickup = pickup
            self.drawnDestination = destination
            self.lastFailureWasTransient = false
            self.loadingState = .loaded
            onRouteResolved?(true)

        } catch is CancellationError {
            // Task was cancelled (view disappeared) - don't update state
            return
        } catch let error as MapError {
            // A lookup that failed because the task was cancelled says nothing about the route.
            guard !Task.isCancelled else { return }
            // Handle specific map errors with more detail
            AppLogger.error("map", "RouteMapView MapError: \(error.errorDescription ?? "unknown") | Pickup: \(pickup) | Destination: \(destination)")
            self.drawnPickup = nil
            self.drawnDestination = nil
            if NetworkMonitor.shared.isConnected {
                // The address could not be found, or no road connects the two.
                self.lastFailureWasTransient = false
                self.loadingState = .error(Self.message(for: error))
                onRouteResolved?(false)
            } else {
                // Offline, every lookup fails the way an unknown address does. That is a
                // connection problem: keep Retry, and do not tell the ride screen there is no route.
                self.lastFailureWasTransient = true
                self.loadingState = .error("route_load_error".localized)
            }
        } catch {
            guard !Task.isCancelled else { return }
            // Throttling, a server failure or a dropped connection: retryable, and not "no route".
            AppLogger.error("map", "RouteMapView error: \(error.localizedDescription) | Pickup: \(pickup) | Destination: \(destination)")
            self.drawnPickup = nil
            self.drawnDestination = nil
            self.lastFailureWasTransient = true
            self.loadingState = .error("route_load_error".localized)
        }
    }

    /// Localized text for a definitive failure (`MapError.errorDescription` is English only).
    private static func message(for error: MapError) -> String {
        if case .routeNotFound = error {
            return "route_not_found".localized
        }
        return "route_address_not_found".localized
    }
}

/// What a route load depends on. `.task(id:)` restarts the load when any of it changes: an
/// edited address redraws the route, and Retry starts a new attempt.
private struct RouteLoadKey: Equatable {
    let pickup: String
    let destination: String
    let attempt: Int
}

// MARK: - Preview

#Preview("Route Map") {
    VStack(spacing: 16) {
        RouteMapView(
            pickup: "Space Needle, Seattle, WA",
            destination: "Pike Place Market, Seattle, WA"
        )
        
        RouteMapView(
            pickup: "Seattle-Tacoma International Airport",
            destination: "University of Washington, Seattle"
        )
    }
    .padding()
}
