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
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var communityContext = CommunityContext.shared
    
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
                    case .leaderboard:
                        LeaderboardView()
                    }
                }
            }
            .navigationTitle(navigationTitleText)
            // One membership: no title menu at all, so the screen is unchanged from the previous build.
            .communityTitleMenu(enabled: communityContext.hasMultipleCommunities) {
                ForEach(communityContext.activeMemberships) { membership in
                    let isSelected = membership.communityId == communityContext.communityTabId
                    Button {
                        communityContext.communityTabId = membership.communityId
                    } label: {
                        if isSelected {
                            Label(membership.name, systemImage: "checkmark")
                        } else {
                            Text(membership.name)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    BellButton {
                        navigationCoordinator.pendingIntent = .notifications
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
            .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
                if case .townHallPost = intent {
                    selectedView = .townHall
                }
            }
            .trackScreen("Community")
        }
    }

    /// `community_title` with one membership; otherwise the Community tab's community name.
    private var navigationTitleText: String {
        guard communityContext.hasMultipleCommunities else { return "community_title".localized }
        return communityContext.name(for: communityContext.communityTabId) ?? "community_title".localized
    }
}

// MARK: - Community Header View

struct CommunityHeaderView: View {
    @Binding var selectedView: CommunityTabView.CommunityView
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("community_view_picker".localized, selection: $selectedView) {
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
        .environment(AppState())
}


