//
//  RequestsDashboardView.swift
//  NaarsCars
//
//  Unified dashboard view for displaying all requests (rides + favors)
//

import SwiftUI
import SwiftData
import UIKit

/// Unified dashboard view for all requests
struct RequestsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RequestsDashboardViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @State private var showCreateRide = false
    @State private var showCreateFavor = false
    @State private var selectedRideId: UUID?
    @State private var selectedFavorId: UUID?
    @State private var pendingRideNavigation: UUID?
    @State private var pendingFavorNavigation: UUID?
    @State private var highlightedRequestKey: String?
    @State private var highlightWorkItem: DispatchWorkItem?
    
    var body: some View {
        NavigationStack {
            // List Content (map view removed)
            listContentView
            .id("app.entry.enterApp")
            .navigationTitle("Requests")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    BellButton {
                        navigationCoordinator.pendingIntent = .notifications
                        AppLogger.info("requests", "Bell tapped")
                    }

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
                            .font(.naarsTitle3)
                    }
                    .accessibilityIdentifier("requests.createMenu")
                    .accessibilityLabel("Create new request")
                    .accessibilityHint("Double-tap to create a new ride or favor request")
                }
            }
            .sheet(isPresented: $showCreateRide, onDismiss: {
                if let rideId = pendingRideNavigation {
                    selectedRideId = rideId
                    pendingRideNavigation = nil
                }
            }) {
                CreateRideView { rideId in
                    pendingRideNavigation = rideId
                }
            }
            .sheet(isPresented: $showCreateFavor, onDismiss: {
                if let favorId = pendingFavorNavigation {
                    selectedFavorId = favorId
                    pendingFavorNavigation = nil
                }
            }) {
                CreateFavorView { favorId in
                    pendingFavorNavigation = favorId
                }
            }
            .navigationDestination(item: $selectedRideId) { rideId in
                RideDetailView(rideId: rideId)
            }
            .navigationDestination(item: $selectedFavorId) { favorId in
                FavorDetailView(favorId: favorId)
            }
            .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
                guard let intent else { return }
                switch intent {
                case .ride(let rideId, let anchor):
                    selectedRideId = rideId
                    if anchor == nil {
                        navigationCoordinator.pendingIntent = nil
                    }
                case .favor(let favorId, let anchor):
                    selectedFavorId = favorId
                    if anchor == nil {
                        navigationCoordinator.pendingIntent = nil
                    }
                default:
                    break
                }
            }
            .task {
                // ViewModel now uses SwiftData for its source of truth
                viewModel.setup(modelContext: modelContext)
                await viewModel.loadRequests()
                viewModel.setupRealtimeSubscription()
            }
            .onDisappear {
                viewModel.cleanupRealtimeSubscription()
            }
            .trackScreen("RequestsDashboard")
        }
    }
    
    // MARK: - List Content View
    
    @ViewBuilder
    private var listContentView: some View {
        let filteredRequests = viewModel.filteredRequests
        
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Constants.Spacing.md, pinnedViews: [.sectionHeaders]) {
                    Section(header: filterHeaderView) {
                        if viewModel.isLoading && filteredRequests.isEmpty {
                            // Show skeleton loading
                            VStack(spacing: Constants.Spacing.md) {
                                ForEach(0..<3, id: \.self) { _ in
                                    SkeletonRequestCard()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 16)
                        } else if let error = viewModel.error {
                            ErrorView(
                                error: error,
                                retryAction: {
                                    Task {
                                        await viewModel.loadRequests()
                                    }
                                }
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                            .padding(.top, 24)
                        } else if filteredRequests.isEmpty {
                            EmptyStateView(
                                icon: "list.bullet.rectangle",
                                title: "No Requests Available",
                                message: filterEmptyMessage,
                                actionTitle: nil,
                                action: nil,
                                customImage: "naars_requests_icon"
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                            .padding(.top, 24)
                        } else {
                            ForEach(filteredRequests) { request in
                                let unreadCount = viewModel.requestNotificationSummaries[request.notificationKey]?.unreadCount ?? 0
                                let isHighlighted = highlightedRequestKey == request.notificationKey
                                NavigationLink(destination: destinationView(for: request)) {
                                    RequestCardView(request: request, unreadCount: unreadCount)
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    if let target = viewModel.notificationTarget(for: request) {
                                        switch request {
                                        case .ride(let ride):
                                            navigationCoordinator.pendingIntent = .ride(ride.id, anchor: target)
                                        case .favor(let favor):
                                            navigationCoordinator.pendingIntent = .favor(favor.id, anchor: target)
                                        }
                                    }
                                })
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("requests.card")
                .accessibilityHint("Double-tap to view request details")
                .padding(.horizontal)
                                .id(request.notificationKey)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            Color.accentColor.opacity(0.6),
                                            lineWidth: isHighlighted ? 2 : 0
                                        )
                                )
                                .animation(.easeInOut(duration: 0.2), value: isHighlighted)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .accessibilityIdentifier("requests.scroll")
            .refreshable {
                await viewModel.refreshRequests()
            }
            .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
                guard case .requestListScroll(let key) = intent else { return }
                scrollToRequest(key, proxy: proxy)
                navigationCoordinator.pendingIntent = nil
            }
        }
    }

    private var filterHeaderView: some View {
        VStack(spacing: 0) {
            // Filter tiles (Open Requests, My Requests, Claimed Requests)
            FilterTilesView(
                selectedFilter: $viewModel.filter,
                badgeCounts: viewModel.filterBadgeCounts
            ) { newFilter in
                viewModel.filterRequests(newFilter)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.naarsBackgroundSecondary)

            Divider()
        }
        .background(Color.naarsBackgroundSecondary)
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

    private func scrollToRequest(_ key: String, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut) {
            proxy.scrollTo(key, anchor: .center)
        }
        highlightRequest(key)
    }

    private func highlightRequest(_ key: String) {
        highlightWorkItem?.cancel()
        highlightedRequestKey = key
        let workItem = DispatchWorkItem {
            if highlightedRequestKey == key {
                highlightedRequestKey = nil
            }
        }
        highlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }
}

// MARK: - Filter Tiles View

struct FilterTilesView: View {
    @Binding var selectedFilter: RequestFilter
    let badgeCounts: [RequestFilter: Int]
    let onFilterChanged: (RequestFilter) -> Void
    
    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            ForEach(RequestFilter.allCases, id: \.self) { filter in
                FilterTile(
                    title: filter.rawValue,
                    isSelected: selectedFilter == filter,
                    badgeCount: badgeCounts[filter] ?? 0
                ) {
                    selectedFilter = filter
                    onFilterChanged(filter)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Filter Tile

struct FilterTile: View {
    let title: String
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.naarsSubheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                
                HStack {
                    Spacer()
                    if let badgeText {
                        Text(badgeText)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .accessibilityLabel("\(badgeCount) unseen notifications")
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("requests.filter.\(title)")
        .accessibilityLabel("\(title) filter\(isSelected ? ", selected" : "")")
        .accessibilityHint("Double-tap to show \(title.lowercased()) requests")
        .simultaneousGesture(TapGesture().onEnded {
            HapticManager.selectionChanged()
        })
    }

    private var badgeText: String? {
        guard badgeCount > 0 else { return nil }
        return badgeCount > 9 ? "9+" : "\(badgeCount)"
    }
}

// MARK: - Request Card View

struct RequestCardView: View {
    let request: RequestItem
    let unreadCount: Int
    
    var body: some View {
        Group {
            switch request {
            case .ride(let ride):
                RideCard(ride: ride, unreadCount: unreadCount)
            case .favor(let favor):
                FavorCard(favor: favor, unreadCount: unreadCount)
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
                
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
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
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    RequestsDashboardView()
        .environmentObject(AppState())
}
