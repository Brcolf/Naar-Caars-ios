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
    @State private var pickupCoordinate: CLLocationCoordinate2D?
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var cameraPosition: MapCameraPosition
    @State private var loadingState: MapLoadingState = .loading
    @State private var retryCount = 0
    @State private var loadId = UUID()  // Force task re-run on view appear
    
    // Default Seattle center
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    
    // Maximum retry attempts
    private static let maxRetries = 2
    
    init(pickup: String, destination: String) {
        self.pickup = pickup
        self.destination = destination
        
        // Initial camera position (will be updated when coordinates are available)
        let initialRegion = MKCoordinateRegion(
            center: Self.defaultCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        _cameraPosition = State(initialValue: .region(initialRegion))
    }
    
    var body: some View {
        contentView
            .task(id: loadId) {
                await loadRoute()
            }
            .onAppear {
                // Reset state and force reload when view appears
                if loadingState != .loading && pickupCoordinate == nil {
                    loadingState = .loading
                    loadId = UUID()
                }
            }
            .onChange(of: retryCount) { _, _ in
                // Trigger reload on retry
                loadId = UUID()
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
                errorView(message: "Route unavailable")
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
                Text("Loading route...")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 200)
        .cornerRadius(8)
    }
    
    private func mapView(pickupCoord: CLLocationCoordinate2D, destCoord: CLLocationCoordinate2D) -> some View {
        Map(position: $cameraPosition) {
            // Route polyline (drawn first so it appears below markers)
            if let route = route {
                MapPolyline(route.polyline)
                    .stroke(Color.rideAccent, lineWidth: 4)
            }
            
            // Pickup marker
            Annotation("Pickup", coordinate: pickupCoord) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                }
            }
            
            // Destination marker
            Annotation("Destination", coordinate: destCoord) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.rideAccent)
                        .font(.system(size: 20))
                }
            }
        }
        .frame(height: 200)
        .cornerRadius(8)
        .disabled(true) // Disable interaction for compact view
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
                
                if retryCount < Self.maxRetries {
                    Button {
                        retryCount += 1
                        // loadId change is handled by onChange
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    }
                }
            }
            .padding()
        }
        .frame(height: 200)
        .cornerRadius(8)
    }
    
    private func loadRoute() async {
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
            
            self.loadingState = .loaded
            
        } catch is CancellationError {
            // Task was cancelled (view disappeared) - don't update state
            return
        } catch let error as MapError {
            // Handle specific map errors with more detail
            print("🗺️ [RouteMapView] MapError: \(error.errorDescription ?? "unknown")")
            print("🗺️ [RouteMapView] Pickup: \(pickup)")
            print("🗺️ [RouteMapView] Destination: \(destination)")
            self.loadingState = .error(error.errorDescription ?? "Route unavailable")
        } catch {
            // Handle generic errors with details
            print("🗺️ [RouteMapView] Error: \(error.localizedDescription)")
            print("🗺️ [RouteMapView] Pickup: \(pickup)")
            print("🗺️ [RouteMapView] Destination: \(destination)")
            self.loadingState = .error("Could not load route")
        }
    }
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
