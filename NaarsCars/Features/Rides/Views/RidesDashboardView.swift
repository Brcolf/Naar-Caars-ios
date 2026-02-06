//
//  RidesDashboardView.swift
//  NaarsCars
//
//  Dashboard view for displaying all ride requests
//

import SwiftUI
import SwiftData

/// Dashboard view for ride requests
struct RidesDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RidesDashboardViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @State private var showCreateRide = false
    @State private var navigateToRide: UUID?
    @AppStorage("rides_view_mode") private var viewMode: ViewMode = .list
    
    // SwiftData Query for "Zero-Spinner" experience
    @Query(sort: \SDRide.date, order: .forward) private var sdRides: [SDRide]
    
    enum ViewMode: String, CaseIterable {
        case list = "list"
        case map = "map"
        
        var displayName: String {
            switch self {
            case .list: return "common_list".localized
            case .map: return "common_map".localized
            }
        }
        
        var iconName: String {
            switch self {
            case .list: return "list.bullet"
            case .map: return "map"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode toggle (List/Map)
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityLabel("View mode")
                .accessibilityHint("Switch between list and map view")
                
                // Filter segmented picker (only show for list view)
                if viewMode == .list {
                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(RideFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Ride filter")
                    .accessibilityHint("Filter rides by category")
                    .onChange(of: viewModel.filter) { _, newFilter in
                        viewModel.filterRides(newFilter)
                    }
                }
                
                // Content
                Group {
                    switch viewMode {
                    case .list:
                        listContentView
                    case .map:
                        mapContentView
                    }
                }
            }
            .navigationTitle("rides_dashboard_title".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateRide = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.naarsTitle3)
                    }
                    .accessibilityLabel("Create ride")
                    .accessibilityHint("Double-tap to create a new ride request")
                }
            }
            .sheet(isPresented: $showCreateRide) {
                CreateRideView { rideId in
                    // Navigate to the newly created ride after sheet dismisses
                    navigateToRide = rideId
                }
            }
            .navigationDestination(item: $navigateToRide) { rideId in
                RideDetailView(rideId: rideId)
            }
            .onChange(of: navigationCoordinator.navigateToRide) { _, rideId in
                if let rideId = rideId {
                    navigateToRide = rideId
                    navigationCoordinator.navigateToRide = nil
                }
            }
            .task {
                if viewMode == .list {
                    viewModel.setup(modelContext: modelContext)
                    await viewModel.loadRides()
                    viewModel.setupRealtimeSubscription()
                }
            }
            .onDisappear {
                viewModel.cleanupRealtimeSubscription()
            }
        }
    }
    
    // MARK: - List Content View
    
    @ViewBuilder
    private var listContentView: some View {
        let filteredRides = viewModel.getFilteredRides(sdRides: sdRides)
        
        if viewModel.isLoading && filteredRides.isEmpty {
            // Show skeleton loading
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonRideCard()
                    }
                }
                .padding()
            }
        } else if let error = viewModel.error {
            ErrorView(
                error: error,
                retryAction: {
                    Task {
                        await viewModel.loadRides()
                    }
                }
            )
        } else if filteredRides.isEmpty {
            EmptyStateView(
                icon: "car.fill",
                title: "No Rides Available",
                message: filterEmptyMessage,
                actionTitle: "Create Ride",
                action: {
                    showCreateRide = true
                }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(filteredRides) { ride in
                        NavigationLink(destination: RideDetailView(rideId: ride.id)) {
                            RideCard(ride: ride)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.refreshRides()
            }
        }
    }
    
    // MARK: - Map Content View
    
    @ViewBuilder
    private var mapContentView: some View {
        RequestMapView(
            onRideSelected: { rideId in
                navigateToRide = rideId
            }
        )
    }
    
    private var filterEmptyMessage: String {
        switch viewModel.filter {
        case .all:
            return "There are no ride requests at this time. Be the first to post one!"
        case .mine:
            return "You haven't posted any ride requests yet. Create your first one!"
        case .claimed:
            return "You haven't claimed any rides yet. Browse all rides to find one to help with!"
        }
    }
}

#Preview {
    RidesDashboardView()
}




