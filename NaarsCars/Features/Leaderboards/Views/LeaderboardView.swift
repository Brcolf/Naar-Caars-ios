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
                    HapticManager.selectionChanged()
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
                        title: "leaderboard_no_rankings".localized,
                        message: "leaderboard_be_first".localized
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
                                Text("leaderboard_your_rank".localized(with: userRank))
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
            .navigationTitle("leaderboard_title".localized)
            .task {
                await viewModel.loadLeaderboard()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .trackScreen("Leaderboard")
        }
    }
}

#Preview {
    LeaderboardView()
}
