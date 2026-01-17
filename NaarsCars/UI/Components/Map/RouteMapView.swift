//
//  RouteMapView.swift
//  NaarsCars
//
//  Compact map view showing route between two points
//

import SwiftUI
import MapKit

/// Compact map view showing a route between pickup and destination
struct RouteMapView: View {
    let pickup: String
    let destination: String
    @State private var pickupCoordinate: CLLocationCoordinate2D?
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var cameraPosition: MapCameraPosition
    @State private var isLoading = true
    
    // Default Seattle center
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    
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
        Group {
            if isLoading {
                // Loading placeholder
                ZStack {
                    Color(.systemGray5)
                    ProgressView()
                }
                .frame(height: 200)
                .cornerRadius(8)
            } else if let pickupCoord = pickupCoordinate,
                      let destCoord = destinationCoordinate {
                // Map with route markers
                Map(position: $cameraPosition) {
                    // Pickup marker
                    Annotation("Pickup", coordinate: pickupCoord) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.rideAccent)
                            .font(.title2)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    
                    // Destination marker
                    Annotation("Destination", coordinate: destCoord) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.rideAccent)
                            .font(.title2)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
                .frame(height: 200)
                .cornerRadius(8)
                .disabled(true) // Disable interaction for compact view
            } else {
                // Error state
                ZStack {
                    Color(.systemGray5)
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Route unavailable")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 200)
                .cornerRadius(8)
            }
        }
        .task {
            await loadRoute()
        }
    }
    
    private func loadRoute() async {
        let mapService = MapService.shared
        
        do {
            // Geocode both addresses
            async let pickupTask = mapService.geocode(address: pickup)
            async let destinationTask = mapService.geocode(address: destination)
            
            let pickupCoord = try await pickupTask
            let destCoord = try await destinationTask
            
            // Calculate route
            let calculatedRoute = try await mapService.calculateRoute(from: pickupCoord, to: destCoord)
            
            // Update state on main thread
            await MainActor.run {
                self.pickupCoordinate = pickupCoord
                self.destinationCoordinate = destCoord
                self.route = calculatedRoute
                self.isLoading = false
                
                // Update camera position to show both points
                let coordinates = [pickupCoord, destCoord]
                let region = MKCoordinateRegion(coordinates: coordinates) ?? MKCoordinateRegion(
                    center: pickupCoord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                self.cameraPosition = .region(region)
            }
        } catch {
            // If geocoding or routing fails, still try to show coordinates if we have them
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Helper Extension

extension MKCoordinateRegion {
    /// Create a region that encompasses all given coordinates
    init?(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return nil }
        
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        let minLat = latitudes.min()!
        let maxLat = latitudes.max()!
        let minLon = longitudes.min()!
        let maxLon = longitudes.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let latDelta = (maxLat - minLat) * 1.5 // Add padding
        let lonDelta = (maxLon - minLon) * 1.5 // Add padding
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(latDelta, 0.01), // Minimum span
            longitudeDelta: max(lonDelta, 0.01) // Minimum span
        )
        
        self.init(center: center, span: span)
    }
}

#Preview {
    VStack {
        RouteMapView(
            pickup: "123 Main St, Seattle, WA",
            destination: "456 Pine St, Seattle, WA"
        )
    }
    .padding()
}
