//
//  CommunityTabView.swift
//  NaarsCars
//
//  Unified Community view combining Town Hall and Leaderboard
//

import SwiftUI

/// Unified Community tab that combines Town Hall and Leaderboard
struct CommunityTabView: View {
    @State private var selectedView: CommunityView = .townHall
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    
    enum CommunityView: String, CaseIterable {
        case townHall = "community_town_hall"
        case leaderboard = "community_leaderboard"
        
        var localizedKey: String {
            switch self {
            case .townHall: return "community_town_hall"
            case .leaderboard: return "community_leaderboard"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Visual header with icon
                CommunityHeaderView(selectedView: $selectedView)
                
                Divider()
                
                // Content based on selection
                Group {
                    switch selectedView {
                    case .townHall:
                        TownHallFeedView()
                            .id("townHall") // Force view recreation when switching
                    case .leaderboard:
                        LeaderboardView()
                            .id("leaderboard") // Force view recreation when switching
                    }
                }
            }
            .navigationTitle("community_title".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    BellButton {
                        navigationCoordinator.navigateToNotifications = true
                        AppLogger.info("community", "Bell tapped")
                    }
                }
            }
            .onAppear {
                // Clear community badge when viewing Community tab
                Task {
                    await BadgeCountManager.shared.clearCommunityBadge()
                }
            }
            .onChange(of: navigationCoordinator.townHallNavigationTarget) { _, newTarget in
                if newTarget != nil {
                    selectedView = .townHall
                }
            }
            .trackScreen("Community")
        }
    }
}

// MARK: - Community Header View

struct CommunityHeaderView: View {
    @Binding var selectedView: CommunityTabView.CommunityView
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("Community View", selection: $selectedView) {
                ForEach(CommunityTabView.CommunityView.allCases, id: \.self) { view in
                    Text(view.rawValue.localized).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 8)
            .padding(.horizontal)
            .accessibilityIdentifier("community.segmented")
        }
        .padding(.bottom, 12)
        .background(Color.naarsBackgroundSecondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("community.header")
    }
}

#Preview {
    CommunityTabView()
        .environmentObject(AppState())
}


