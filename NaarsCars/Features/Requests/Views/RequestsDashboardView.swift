//
//  RequestsDashboardView.swift
//  NaarsCars
//
//  Unified dashboard view for displaying all requests (rides + favors)
//

import SwiftUI

/// Unified dashboard view for all requests
struct RequestsDashboardView: View {
    @StateObject private var viewModel = RequestsDashboardViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @State private var showCreateRide = false
    @State private var showCreateFavor = false
    @State private var navigateToRide: UUID?
    @State private var navigateToFavor: UUID?
    @AppStorage("requests_view_mode") private var viewMode: ViewMode = .list
    
    enum ViewMode: String {
        case list = "list"
        case map = "map"
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Filter tiles (Open Requests, My Requests, Claimed by Me)
                    FilterTilesView(selectedFilter: $viewModel.filter) { newFilter in
                        viewModel.filterRequests(newFilter)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // Content (List or Map)
                    Group {
                        switch viewMode {
                        case .list:
                            listContentView
                        case .map:
                            mapContentView
                        }
                    }
                }
                
                // Floating map toggle button (bottom right, above nav bar)
                if viewMode == .list {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewMode = .map
                        }
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 90) // Above tab bar
                } else {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewMode = .list
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 90) // Above tab bar
                }
            }
            .navigationTitle("Requests")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showCreateRide = true
                        } label: {
                            Label("Create Ride", systemImage: "car.fill")
                        }
                        
                        Button {
                            showCreateFavor = true
                        } label: {
                            Label("Create Favor", systemImage: "hand.raised.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreateRide) {
                CreateRideView()
            }
            .sheet(isPresented: $showCreateFavor) {
                CreateFavorView()
            }
            .navigationDestination(item: $navigateToRide) { rideId in
                RideDetailView(rideId: rideId)
            }
            .navigationDestination(item: $navigateToFavor) { favorId in
                FavorDetailView(favorId: favorId)
            }
            .onChange(of: navigationCoordinator.navigateToRide) { _, rideId in
                if let rideId = rideId {
                    navigateToRide = rideId
                    navigationCoordinator.navigateToRide = nil
                }
            }
            .onChange(of: navigationCoordinator.navigateToFavor) { _, favorId in
                if let favorId = favorId {
                    navigateToFavor = favorId
                    navigationCoordinator.navigateToFavor = nil
                }
            }
            .task {
                if viewMode == .list {
                    await viewModel.loadRequests()
                    viewModel.setupRealtimeSubscription()
                }
            }
            .onChange(of: viewMode) { _, newMode in
                if newMode == .list {
                    Task {
                        await viewModel.loadRequests()
                        viewModel.setupRealtimeSubscription()
                    }
                } else {
                    viewModel.cleanupRealtimeSubscription()
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
        if viewModel.isLoading && viewModel.requests.isEmpty {
            // Show skeleton loading
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonRequestCard()
                    }
                }
                .padding()
            }
        } else if let error = viewModel.error {
            ErrorView(
                error: error,
                retryAction: {
                    Task {
                        await viewModel.loadRequests()
                    }
                }
            )
        } else if viewModel.requests.isEmpty {
            EmptyStateView(
                icon: "list.bullet.rectangle",
                title: "No Requests Available",
                message: filterEmptyMessage,
                actionTitle: nil,
                action: nil
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.requests) { request in
                        NavigationLink(destination: destinationView(for: request)) {
                            RequestCardView(request: request)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.refreshRequests()
            }
        }
    }
    
    // MARK: - Map Content View
    
    @ViewBuilder
    private var mapContentView: some View {
        RequestMapView(
            filter: viewModel.filter,
            onRideSelected: { rideId in
                navigateToRide = rideId
            },
            onFavorSelected: { favorId in
                navigateToFavor = favorId
            }
        )
        .onChange(of: viewModel.filter) { _, newFilter in
            // Reload map when filter changes
            Task {
                await viewModel.loadRequests()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    @ViewBuilder
    private func destinationView(for request: RequestItem) -> some View {
        switch request {
        case .ride(let ride):
            RideDetailView(rideId: ride.id)
        case .favor(let favor):
            FavorDetailView(favorId: favor.id)
        }
    }
    
    private var filterEmptyMessage: String {
        switch viewModel.filter {
        case .open:
            return "There are no open requests at this time. Be the first to post one!"
        case .mine:
            return "You haven't posted any requests yet. Create your first one!"
        case .claimed:
            return "You haven't claimed any requests yet. Browse all requests to find one to help with!"
        }
    }
}

// MARK: - Filter Tiles View

struct FilterTilesView: View {
    @Binding var selectedFilter: RequestFilter
    let onFilterChanged: (RequestFilter) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(RequestFilter.allCases, id: \.self) { filter in
                FilterTile(
                    title: filter.rawValue,
                    isSelected: selectedFilter == filter
                ) {
                    selectedFilter = filter
                    onFilterChanged(filter)
                }
            }
        }
    }
}

// MARK: - Filter Tile

struct FilterTile: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Request Card View

struct RequestCardView: View {
    let request: RequestItem
    
    var body: some View {
        Group {
            switch request {
            case .ride(let ride):
                RideCard(ride: ride)
            case .favor(let favor):
                FavorCard(favor: favor)
            }
        }
    }
}

// MARK: - Skeleton Request Card

struct SkeletonRequestCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray4))
                        .frame(width: 120, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray4))
                        .frame(width: 80, height: 12)
                }
                
                Spacer()
            }
            
            Divider()
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray4))
                .frame(height: 20)
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray4))
                .frame(height: 16)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    RequestsDashboardView()
        .environmentObject(AppState())
}

