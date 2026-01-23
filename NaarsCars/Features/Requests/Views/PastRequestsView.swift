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
    @State private var navigateToRide: UUID?
    @State private var navigateToFavor: UUID?
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
        case myRequests = "My Past Requests"
        case helpedWith = "Requests I've Helped With"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter toggle
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(PastRequestFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
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
                        title: "No Past Requests",
                        message: filterEmptyMessage,
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.requests) { request in
                                NavigationLink(destination: destinationView(for: request)) {
                                    RequestCardView(request: request, showsUnseenIndicator: false)
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
            .navigationTitle("Past Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
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
            .navigationDestination(item: $navigateToRide) { rideId in
                RideDetailView(rideId: rideId)
            }
            .navigationDestination(item: $navigateToFavor) { favorId in
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
            return "You haven't posted any requests that are more than 12 hours old."
        case .helpedWith:
            return "You haven't helped with any requests that are more than 12 hours old."
        }
    }
}

