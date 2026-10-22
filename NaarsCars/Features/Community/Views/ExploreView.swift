//
//  ExploreView.swift
//  NaarsCars
//
//  The Explore tab: the community search field, My communities as the stack's root, and the bell
//

import SwiftUI

/// The Explore tab (the trailing search-role tab), for guests and members alike. My communities is
/// the root of its stack and opens the community routes (`.myCommunities`, `.joinCommunity`,
/// `.pendingMembers`, `.communityReports`, `.communityMembers`) itself. While the search field
/// holds a search, its results are drawn over My communities, which stays mounted.
struct ExploreView: View {
    @Environment(AppState.self) private var appState
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @StateObject private var search = ExploreSearchViewModel()
    /// The community page opened from a search result.
    @State private var communityPageTarget: UUID?
    /// Start a community from the results: My communities opens its own sheet.
    @State private var startCommunityRequested = false

    var body: some View {
        NavigationStack {
            ZStack {
                MyCommunitiesView(
                    onUseMyLocation: { Task { await search.useMyLocation() } },
                    isLocating: search.isLocating,
                    startCommunityRequested: $startCommunityRequested,
                    hasSearchScreenOnTop: communityPageTarget != nil
                )
                .accessibilityHidden(search.showsResults)

                if search.showsResults {
                    CommunitySearchResultsView(
                        viewModel: search,
                        isGuest: appState.isGuest,
                        membership: { CommunityContext.shared.membership(for: $0) },
                        onSelect: { communityPageTarget = $0 },
                        onStartCommunity: { startCommunityRequested = true }
                    )
                }
            }
            .navigationDestination(item: $communityPageTarget) { communityId in
                // Another community in place needs a fresh view model (the Members identity rule).
                CommunityPageView(communityId: communityId)
                    .id(communityId)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Everyone gets the bell; a guest's tap reaches MainTabView's sign-in prompt.
                    BellButton {
                        navigationCoordinator.pendingIntent = .notifications
                        AppLogger.info("community", "Bell tapped on Explore")
                    }
                }
            }
        }
        .searchable(text: $search.query, prompt: "explore_search_prompt".localized)
        .toast(message: $search.locationNotice, style: .info)
        // An Explore route (a push, a link, Find communities) is opened by My communities: the
        // search and a page opened from it give way so that route shows.
        .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
            guard let intent, MyCommunitiesView.exploreRoute(for: intent) != nil else { return }
            communityPageTarget = nil
            if search.showsResults || !search.query.isEmpty {
                search.clear()
            }
        }
        .trackScreen("Explore")
    }
}

#if DEBUG
#Preview {
    ExploreView()
        .environment(AppState())
}
#endif
