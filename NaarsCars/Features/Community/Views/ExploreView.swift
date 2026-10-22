//
//  ExploreView.swift
//  NaarsCars
//
//  The Explore tab: My communities as the stack's root, with the bell
//

import SwiftUI

/// The Explore tab (the trailing search-role tab), for guests and members alike. My communities is
/// the root of its stack and opens the community routes (`.myCommunities`, `.joinCommunity`,
/// `.pendingMembers`, `.communityReports`, `.communityMembers`) itself.
struct ExploreView: View {
    @State private var navigationCoordinator = NavigationCoordinator.shared

    var body: some View {
        NavigationStack {
            MyCommunitiesView()
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
        .trackScreen("Explore")
    }
}

#if DEBUG
#Preview {
    ExploreView()
}
#endif
