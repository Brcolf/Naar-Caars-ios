//
//  LeaderboardView.swift
//  NaarsCars
//
//  Leaderboard view showing community rankings
//

import SwiftUI

/// Leaderboard view showing community rankings.
/// Hosted inside CommunityTabView's NavigationStack; it must not open a stack of its own, or it
/// draws a second navigation bar under the Community one and pushes profiles inside the segment.
struct LeaderboardView: View {
    @StateObject private var viewModel = LeaderboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Time period picker
            Picker("leaderboard_period_label".localized, selection: $viewModel.selectedPeriod) {
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
                .scrollContentBackground(.hidden)
                .background(Color.naarsBackground)
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

                    // Spotlights section
                    if !viewModel.spotlights.isEmpty {
                        Section {
                            ForEach(viewModel.spotlights) { spotlight in
                                NavigationLink(destination: PublicProfileView(userId: spotlight.userId)) {
                                    SpotlightCard(spotlight: spotlight)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text("leaderboard_spotlights".localized)
                                .font(.naarsHeadline)
                                .foregroundColor(.primary)
                                .textCase(nil)
                                .padding(.top, 8)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.naarsBackground)
            }
        }
        .task {
            await viewModel.loadLeaderboard()
        }
        .refreshable {
            await viewModel.refresh()
        }
        // A refresh that fails while rankings are on screen keeps them and says so.
        .errorBanner(message: $viewModel.bannerMessage)
        .trackScreen("Leaderboard")
    }
}

#Preview {
    // The view relies on its host's NavigationStack (CommunityTabView in the app).
    NavigationStack {
        LeaderboardView()
    }
}
