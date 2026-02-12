//
//  PastRequestsView.swift
//  NaarsCars
//
//  View for displaying past requests (requests older than 12 hours)
//

import SwiftUI

/// View for displaying past requests
struct PastRequestsView: View {
    @StateObject private var viewModel = PastRequestsViewModel()
    @State private var selectedFilter: PastRequestFilter = .myRequests
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPastRideId: UUID?
    @State private var selectedPastFavorId: UUID?
    @State private var showReviewPrompt: PendingReviewPrompt?
    
    struct PendingReviewPrompt: Identifiable {
        let id: UUID
        let requestType: String
        let requestId: UUID
        let requestTitle: String
        let fulfillerId: UUID
        let fulfillerName: String
    }
    
    enum PastRequestFilter: String, CaseIterable {
        case myRequests = "ride_edit_my_past_requests"
        case helpedWith = "ride_edit_helped_with"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter toggle
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(PastRequestFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue.localized).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Divider()
                
                // Content
                if viewModel.isLoading && viewModel.requests.isEmpty {
                    // Loading state
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
                                await viewModel.loadRequests(filter: selectedFilter)
                            }
                        }
                    )
                } else if viewModel.requests.isEmpty {
                    EmptyStateView(
                        icon: "clock.fill",
                        title: "ride_edit_no_past_requests".localized,
                        message: filterEmptyMessage,
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.requests) { request in
                                NavigationLink(destination: destinationView(for: request)) {
                                    RequestCardView(request: request, unreadCount: 0)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.refreshRequests(filter: selectedFilter)
                    }
                }
            }
            .navigationTitle("ride_edit_past_requests_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common_close".localized) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadRequests(filter: selectedFilter)
            }
            .onChange(of: selectedFilter) { _, newFilter in
                Task {
                    await viewModel.loadRequests(filter: newFilter)
                }
            }
            .navigationDestination(item: $selectedPastRideId) { rideId in
                RideDetailView(rideId: rideId)
            }
            .navigationDestination(item: $selectedPastFavorId) { favorId in
                FavorDetailView(favorId: favorId)
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
        switch selectedFilter {
        case .myRequests:
            return "ride_edit_no_past_requests_mine".localized
        case .helpedWith:
            return "ride_edit_no_past_requests_helped".localized
        }
    }
}

