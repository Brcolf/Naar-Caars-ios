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
    @Environment(AppState.self) private var appState
    @StateObject private var viewModel = RequestsDashboardViewModel()
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var showCreateRide = false
    @State private var showCreateFavor = false
    @State private var selectedRideId: UUID?
    @State private var selectedFavorId: UUID?
    /// Set once the pending-intent handler's `initial: true` pass has run (see that handler).
    @State private var didReplayInitialIntent = false
    @State private var pendingRideNavigation: UUID?
    @State private var pendingFavorNavigation: UUID?
    @State private var highlightedRequestKey: String?
    @State private var highlightWorkItem: DispatchWorkItem?
    
    var body: some View {
        NavigationStack {
            // List Content (map view removed)
            listContentView
            .id("app.entry.enterApp")
            .navigationTitle("requests_nav_title".localized)
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
                            Label("requests_create_ride".localized, systemImage: "car.fill")
                        }
                        
                        Button {
                            showCreateFavor = true
                        } label: {
                            Label("requests_create_favor".localized, systemImage: "hand.raised.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.naarsTitle3)
                    }
                    .accessibilityIdentifier("requests.createMenu")
                    .accessibilityLabel("requests_create_accessibility".localized)
                    .accessibilityHint("requests_create_hint".localized)
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
            // initial: true also opens a ride or favor whose intent was set before this view
            // existed (a push tapped while the app was not running); onChange alone never fires
            // for a value that is already there.
            .onChange(of: navigationCoordinator.pendingIntent, initial: true) { oldIntent, intent in
                // Old and new are the same value only on the pass that initial: true adds. That
                // pass is tied to the list appearing, so it comes round again on Back from a
                // detail and on return to the tab; it is honoured once per view lifetime.
                let isInitialPass = oldIntent == intent
                if isInitialPass {
                    guard !didReplayInitialIntent else { return }
                    didReplayInitialIntent = true
                }
                guard let intent else { return }
                if isInitialPass {
                    // One main-actor turn later: a push requested in the same update as the
                    // stack's first render can be dropped. Skipped if the intent was consumed or
                    // replaced meanwhile, so it is never applied twice.
                    Task { @MainActor in
                        guard navigationCoordinator.pendingIntent == intent else { return }
                        openRequest(from: intent)
                    }
                    return
                }
                openRequest(from: intent)
            }
            .task {
                // ViewModel now uses SwiftData for its source of truth
                viewModel.setup(modelContext: modelContext)
                // Observe the sync notifications before the first await. A dashboard sync
                // started by the person's own claim / edit / delete on the detail screen can
                // finish while this screen is reappearing; registering after the load left a
                // gap in which that sync's notification was missed and the list stayed stale.
                if !appState.isGuest {
                    viewModel.setupRealtimeSubscription()
                }
                await viewModel.loadRequests()
            }
            .onDisappear { viewModel.stop() }
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
                        } else if let error = viewModel.error, filteredRequests.isEmpty {
                            // Full error panel only when there is nothing to show. With cached
                            // rows on screen the failure is reported by the banner in the
                            // header and the list stays (it used to be replaced by this panel).
                            ErrorView(
                                error: error,
                                retryAction: {
                                    Task {
                                        await viewModel.refreshRequests()
                                    }
                                }
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal)
                            .padding(.top, 24)
                        } else if filteredRequests.isEmpty {
                            EmptyStateView(
                                icon: "list.bullet.rectangle",
                                title: "requests_empty_title".localized,
                                message: filterEmptyMessage,
                                actionTitle: nil,
                                action: nil,
                                customImage: "naars_requests_icon",
                                isCard: true
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
                .accessibilityHint("requests_row_hint".localized)
                .padding(.horizontal)
                                .id(request.notificationKey)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                                        .stroke(
                                            Color.naarsPrimary.opacity(0.6),
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
            .background(Color.naarsBackground)
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
                // Guests have no "mine" / "claimed" data; the tiles were always empty for them.
                filters: appState.isGuest ? [.open] : RequestFilter.allCases,
                badgeCounts: viewModel.filterBadgeCounts
            ) { newFilter in
                viewModel.filterRequests(newFilter)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.naarsBackgroundSecondary)

            // A failed refresh over a list that is still showing its cached rows. Sits in the
            // pinned header so it neither covers the filter tiles nor scrolls away.
            if showsRefreshFailureBanner {
                ErrorBanner(
                    message: "requests_refresh_failed_banner".localized,
                    retryAction: {
                        Task {
                            await viewModel.refreshRequests()
                        }
                    },
                    dismissAction: {
                        viewModel.error = nil
                    }
                )
                .padding(.bottom, Constants.Spacing.sm)
            }

            Divider()
        }
        .background(Color.naarsBackgroundSecondary)
        .animation(.naarsStandard, value: showsRefreshFailureBanner)
    }

    private var showsRefreshFailureBanner: Bool {
        viewModel.error != nil && !viewModel.filteredRequests.isEmpty
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
            return "requests_empty_open".localized
        case .mine:
            return "requests_empty_mine".localized
        case .claimed:
            return "requests_empty_claimed".localized
        }
    }

    /// Opens the ride or favor a pending intent points at; any other intent is left alone.
    /// The intent is cleared here only when it carries no anchor: with one, the detail view
    /// consumes it (`consumeRequestNavigationTarget`).
    private func openRequest(from intent: NavigationIntent) {
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

// MARK: - Filter Tile Height Preference

/// Preference key that collects the maximum intrinsic tile-content height
/// across all tiles so every tile can render at the same height.
private struct TileHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Filter Tiles View

struct FilterTilesView: View {
    @Binding var selectedFilter: RequestFilter
    let filters: [RequestFilter]
    let badgeCounts: [RequestFilter: Int]
    let onFilterChanged: (RequestFilter) -> Void
    @State private var uniformHeight: CGFloat?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Three tiles side by side truncate to "O…" / "M…" / "Cl…" at accessibility sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Constants.Spacing.sm))
        layout {
            ForEach(filters, id: \.self) { filter in
                FilterTile(
                    title: filter.localizedKey.localized,
                    identifier: filter.rawValue,
                    isSelected: selectedFilter == filter,
                    badgeCount: badgeCounts[filter] ?? 0,
                    // Stacked full-width tiles need no shared height; forcing the side-by-side
                    // measurement truncated "Claimed Requests" to one line at accessibility sizes.
                    uniformHeight: dynamicTypeSize.isAccessibilitySize ? nil : uniformHeight
                ) {
                    selectedFilter = filter
                    onFilterChanged(filter)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onPreferenceChange(TileHeightKey.self) { maxHeight in
            if maxHeight > 0 { uniformHeight = maxHeight }
        }
    }
}

// MARK: - Filter Tile

struct FilterTile: View {
    let title: String
    let identifier: String
    let isSelected: Bool
    let badgeCount: Int
    let uniformHeight: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.naarsSubheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    // Measure natural text height and report to parent
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: TileHeightKey.self, value: geo.size.height)
                    })
                    // Apply uniform height once measured — forces all
                    // text blocks to the same height so wrapping is consistent
                    .frame(height: uniformHeight)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.naarsPrimary : Color.naarsInsetBackground)
            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.md, style: .continuous))
            // The count sits on the tile's top trailing corner. It used to be centred on the
            // trailing edge, on top of the label ("My Reques(1)").
            .overlay(alignment: .topTrailing) {
                NotificationBadge(count: badgeCount, cap: 9)
                    .accessibilityLabel("common_unseen_notifications_accessibility".localized(with: badgeCount))
                    .offset(x: Constants.Spacing.xs, y: -Constants.Spacing.xs)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("requests.filter.\(identifier)")
        .accessibilityLabel(isSelected ? "requests_filter_tile_selected_accessibility".localized(with: title) : "requests_filter_tile_accessibility".localized(with: title))
        // The explicit label above replaces the badge's own label, so the count is spoken as
        // the tile's value; without it VoiceOver never said which filter has new activity.
        .accessibilityValue(badgeCount > 0 ? "common_unseen_notifications_accessibility".localized(with: badgeCount) : "")
        .accessibilityHint("requests_filter_tile_hint".localized(with: title.lowercased()))
        .simultaneousGesture(TapGesture().onEnded {
            HapticManager.selectionChanged()
        })
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
                    RoundedRectangle(cornerRadius: Constants.Radius.xs)
                        .fill(Color(.systemGray4))
                        .frame(width: 120, height: 16)
                    RoundedRectangle(cornerRadius: Constants.Radius.xs)
                        .fill(Color(.systemGray4))
                        .frame(width: 80, height: 12)
                }
                
                Spacer()
            }
            
            Divider()
            
            RoundedRectangle(cornerRadius: Constants.Radius.xs)
                .fill(Color(.systemGray4))
                .frame(height: 20)
            
            RoundedRectangle(cornerRadius: Constants.Radius.xs)
                .fill(Color(.systemGray4))
                .frame(height: 16)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.card)
        .cardShadow()
        .redacted(reason: .placeholder)
    }
}

#Preview {
    RequestsDashboardView()
        .environment(AppState())
}
