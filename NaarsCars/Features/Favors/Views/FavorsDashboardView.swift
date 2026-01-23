//
//  FavorsDashboardView.swift
//  NaarsCars
//
//  Dashboard view for displaying all favor requests
//

import SwiftUI
import SwiftData

/// Dashboard view for favor requests
struct FavorsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FavorsDashboardViewModel()
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @State private var showCreateFavor = false
    @State private var navigateToFavor: UUID?
    @AppStorage("favors_view_mode") private var viewMode: ViewMode = .list
    
    // SwiftData Query for "Zero-Spinner" experience
    @Query(sort: \SDFavor.date, order: .forward) private var sdFavors: [SDFavor]
    
    enum ViewMode: String, CaseIterable {
        case list = "list"
        case map = "map"
        
        var displayName: String {
            switch self {
            case .list: return "List"
            case .map: return "Map"
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
                
                // Filter segmented picker (only show for list view)
                if viewMode == .list {
                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(FavorFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .onChange(of: viewModel.filter) { _, newFilter in
                        viewModel.filterFavors(newFilter)
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
            .navigationTitle("Favor Requests")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateFavor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreateFavor) {
                CreateFavorView { favorId in
                    // Navigate to the newly created favor after sheet dismisses
                    navigateToFavor = favorId
                }
            }
            .navigationDestination(item: $navigateToFavor) { favorId in
                FavorDetailView(favorId: favorId)
            }
            .onChange(of: navigationCoordinator.navigateToFavor) { _, favorId in
                if let favorId = favorId {
                    navigateToFavor = favorId
                    navigationCoordinator.navigateToFavor = nil
                }
            }
            .task {
                if viewMode == .list {
                    viewModel.setup(modelContext: modelContext)
                    await viewModel.loadFavors()
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
        let filteredFavors = viewModel.getFilteredFavors(sdFavors: sdFavors)
        
        if viewModel.isLoading && filteredFavors.isEmpty {
            // Show skeleton loading
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonFavorCard()
                    }
                }
                .padding()
            }
        } else if let error = viewModel.error {
            ErrorView(
                error: error,
                retryAction: {
                    Task {
                        await viewModel.loadFavors()
                    }
                }
            )
        } else if filteredFavors.isEmpty {
            EmptyStateView(
                icon: "hand.raised.fill",
                title: "No Favors Available",
                message: filterEmptyMessage,
                actionTitle: "Create Favor",
                action: {
                    showCreateFavor = true
                }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(filteredFavors) { favor in
                        NavigationLink(destination: FavorDetailView(favorId: favor.id)) {
                            FavorCard(favor: favor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .refreshable {
                await viewModel.refreshFavors()
            }
        }
    }
    
    // MARK: - Map Content View
    
    @ViewBuilder
    private var mapContentView: some View {
        RequestMapView(
            onFavorSelected: { favorId in
                navigateToFavor = favorId
            }
        )
    }
    
    private var filterEmptyMessage: String {
        switch viewModel.filter {
        case .all:
            return "There are no favor requests at this time. Be the first to post one!"
        case .mine:
            return "You haven't posted any favor requests yet. Create your first one!"
        case .claimed:
            return "You haven't claimed any favors yet. Browse all favors to find one to help with!"
        }
    }
}

#Preview {
    FavorsDashboardView()
}




