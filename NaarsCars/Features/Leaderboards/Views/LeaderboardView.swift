//
//  LeaderboardView.swift
//  NaarsCars
//
//  Leaderboard view showing community rankings
//

import SwiftUI

/// Leaderboard view showing community rankings
struct LeaderboardView: View {
    @StateObject private var viewModel = LeaderboardViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Time period picker
                Picker("Period", selection: $viewModel.selectedPeriod) {
                    ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: viewModel.selectedPeriod) { _, _ in
                    Task {
                        await viewModel.loadLeaderboard()
                    }
                }
                
                // Content
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    // Skeleton loading
                    List {
                        ForEach(0..<10, id: \.self) { _ in
                            SkeletonLeaderboardRow()
                        }
                    }
                    .listStyle(.plain)
                } else if let error = viewModel.error, viewModel.entries.isEmpty {
                    ErrorView(
                        error: error.localizedDescription,
                        retryAction: {
                            Task {
                                await viewModel.loadLeaderboard()
                            }
                        }
                    )
                } else if viewModel.entries.isEmpty {
                    EmptyStateView(
                        icon: "trophy.fill",
                        title: "No Rankings Yet",
                        message: "Be the first to fulfill a request and appear on the leaderboard!"
                    )
                } else {
                    List {
                        ForEach(viewModel.entries) { entry in
                            NavigationLink(destination: PublicProfileView(userId: entry.userId)) {
                                LeaderboardRow(entry: entry)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Show current user's rank if not in top entries
                        if let userRank = viewModel.currentUserRank,
                           !viewModel.entries.contains(where: { $0.isCurrentUser }) {
                            Divider()
                            
                            HStack {
                                Text("Your Rank: #\(userRank)")
                                    .font(.naarsHeadline)
                                    .foregroundColor(.naarsPrimary)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Leaderboard")
            .task {
                await viewModel.loadLeaderboard()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
}

#Preview {
    LeaderboardView()
}
