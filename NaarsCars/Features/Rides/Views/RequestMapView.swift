//
//  RequestMapView.swift
//  NaarsCars
//
//  Map view for displaying ride and favor requests geographically
//

import SwiftUI
import Foundation
import MapKit
import CoreLocation
internal import Combine

/// Map view displaying ride and favor requests
struct RequestMapView: View {
    @StateObject private var viewModel: RequestMapViewModel
    @State private var selectedRequest: MapRequest?
    @State private var cameraPosition: MapCameraPosition
    
    var onRideSelected: ((UUID) -> Void)?
    var onFavorSelected: ((UUID) -> Void)?
    
    // Default center for map region
    private static let defaultCenter = CLLocationCoordinate2D(latitude: Constants.Map.defaultLatitude, longitude: Constants.Map.defaultLongitude)
    
    init(
        filter: RequestFilter = .open,
        onRideSelected: ((UUID) -> Void)? = nil,
        onFavorSelected: ((UUID) -> Void)? = nil
    ) {
        self.onRideSelected = onRideSelected
        self.onFavorSelected = onFavorSelected
        _viewModel = StateObject(wrappedValue: RequestMapViewModel(filter: filter))
        
        let initialRegion = MKCoordinateRegion(
            center: Self.defaultCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
        _cameraPosition = State(initialValue: .region(initialRegion))
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Map (iOS 17+ API)
            Map(position: $cameraPosition) {
                // User location (built-in)
                UserAnnotation()
                
                // Request pins (both rides and favors are shown together)
                ForEach(viewModel.mapRequests) { request in
                    Annotation(
                        request.title,
                        coordinate: request.coordinate
                    ) {
                        RequestPin(request: request, isSelected: selectedRequest?.id == request.id) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedRequest = request
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea(edges: .top)
            .task {
                await viewModel.loadRequests()
                // Adjust region to fit all requests
                if !viewModel.mapRequests.isEmpty {
                    adjustRegionToFitRequests()
                }
            }
            .onChange(of: viewModel.mapRequests) { _, _ in
                // Adjust region when requests change
                if !viewModel.mapRequests.isEmpty {
                    adjustRegionToFitRequests()
                }
            }
            
            // Bottom sheet for selected request
            if let request = selectedRequest {
                VStack {
                    Spacer()
                    RequestPreviewCard(
                        request: request,
                        onClose: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedRequest = nil
                            }
                        },
                        onViewDetails: {
                            handleViewDetails(for: request)
                            withAnimation(.spring(response: 0.3)) {
                                selectedRequest = nil
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
        }
        .onChange(of: selectedRequest) { _, newValue in
            if let request = newValue {
                // Center map on selected request
                withAnimation(.easeInOut(duration: 0.3)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: request.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Adjust map region to fit all visible requests
    private func adjustRegionToFitRequests() {
        guard !viewModel.mapRequests.isEmpty else { return }
        
        let coordinates = viewModel.mapRequests.map { $0.coordinate }
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLng = longitudes.min(),
              let maxLng = longitudes.max() else {
            return
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        
        let latDelta = max((maxLat - minLat) * 1.3, 0.01) // 30% padding
        let lngDelta = max((maxLng - minLng) * 1.3, 0.01)
        
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        let region = MKCoordinateRegion(center: center, span: span)
        
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(region)
        }
    }
    
    /// Handle view details button tap
    private func handleViewDetails(for request: MapRequest) {
        switch request.type {
        case .ride:
            onRideSelected?(request.id)
        case .favor:
            onFavorSelected?(request.id)
        }
    }
}

// MARK: - View Model

/// ViewModel for map view
@MainActor
final class RequestMapViewModel: ObservableObject {
    @Published var mapRequests: [MapRequest] = []
    @Published var isLoading = false
    
    private let filter: RequestFilter
    private let mapService = MapService.shared
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    
    init(filter: RequestFilter = .open) {
        self.filter = filter
    }
    
    /// Load rides and favors based on filter, then create map requests
    func loadRequests() async {
        isLoading = true
        
        do {
            let currentUserId = authService.currentUserId
            
            // Fetch rides and favors in parallel based on filter
            async let ridesTask: [Ride] = {
                switch filter {
                case .open:
                    return try await rideService.fetchRides(status: .open)
                case .mine:
                    guard let userId = currentUserId else { return [] }
                    return try await rideService.fetchRides(userId: userId)
                case .claimed:
                    guard let userId = currentUserId else { return [] }
                    return try await rideService.fetchRides(claimedBy: userId)
                }
            }()
            
            async let favorsTask: [Favor] = {
                switch filter {
                case .open:
                    return try await favorService.fetchFavors(status: .open)
                case .mine:
                    guard let userId = currentUserId else { return [] }
                    return try await favorService.fetchFavors(userId: userId)
                case .claimed:
                    guard let userId = currentUserId else { return [] }
                    return try await favorService.fetchFavors(claimedBy: userId)
                }
            }()
            
            let rides = try await ridesTask
            let favors = try await favorsTask
            
            // Filter out completed requests
            let filteredRides = rides.filter { $0.status != .completed }
            let filteredFavors = favors.filter { $0.status != .completed }
            
            // Create map requests (geocoding happens here)
            mapRequests = await mapService.createMapRequests(rides: filteredRides, favors: filteredFavors)
            
        } catch {
            AppLogger.error("map", "Error loading requests: \(error.localizedDescription)")
            mapRequests = []
        }
        
        isLoading = false
    }
}

#Preview {
    RequestMapView()
}

