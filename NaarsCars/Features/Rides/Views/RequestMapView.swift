//
//  RequestMapView.swift
//  NaarsCars
//
//  Map view for displaying ride and favor requests geographically
//

import SwiftUI
import MapKit
import CoreLocation

/// Map view displaying ride and favor requests
struct RequestMapView: View {
    @StateObject private var viewModel = RequestMapViewModel()
    @State private var selectedRequest: MapRequest?
    @State private var cameraPosition: MapCameraPosition
    
    var onRideSelected: ((UUID) -> Void)?
    var onFavorSelected: ((UUID) -> Void)?
    
    // Seattle center for default region
    private static let seattleCenter = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    
    init(
        onRideSelected: ((UUID) -> Void)? = nil,
        onFavorSelected: ((UUID) -> Void)? = nil
    ) {
        self.onRideSelected = onRideSelected
        self.onFavorSelected = onFavorSelected
        
        let initialRegion = MKCoordinateRegion(
            center: Self.seattleCenter,
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
                
                // Request pins
                ForEach(viewModel.filteredRequests) { request in
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
            .onAppear {
                Task {
                    await viewModel.loadRequests()
                    // Adjust region to fit all requests
                    if !viewModel.mapRequests.isEmpty {
                        adjustRegionToFitRequests()
                    }
                }
            }
            .onChange(of: viewModel.filteredRequests) { _, _ in
                // Adjust region when filters change
                if !viewModel.filteredRequests.isEmpty {
                    adjustRegionToFitRequests()
                }
            }
            
            // Filter bar overlay
            VStack {
                FilterBar(
                    showRides: $viewModel.showRides,
                    showFavors: $viewModel.showFavors,
                    requestCount: viewModel.filteredRequests.count
                )
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
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
        guard !viewModel.filteredRequests.isEmpty else { return }
        
        let coordinates = viewModel.filteredRequests.map { $0.coordinate }
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
    @Published var showRides = true
    @Published var showFavors = true
    @Published var isLoading = false
    
    var filteredRequests: [MapRequest] {
        mapRequests.filter { request in
            switch request.type {
            case .ride:
                return showRides
            case .favor:
                return showFavors
            }
        }
    }
    
    private let mapService = MapService.shared
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    
    /// Load rides and favors, then create map requests
    func loadRequests() async {
        isLoading = true
        
        do {
            // Fetch rides and favors in parallel
            async let ridesTask: [Ride] = rideService.fetchRides(status: .open)
            async let favorsTask: [Favor] = favorService.fetchFavors(status: .open)
            
            let rides = try await ridesTask
            let favors = try await favorsTask
            
            // Create map requests (geocoding happens here)
            mapRequests = await mapService.createMapRequests(rides: rides, favors: favors)
            
        } catch {
            print("❌ [RequestMapViewModel] Error loading requests: \(error.localizedDescription)")
            mapRequests = []
        }
        
        isLoading = false
    }
}

#Preview {
    RequestMapView()
}

