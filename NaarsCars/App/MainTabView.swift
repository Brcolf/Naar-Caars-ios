//
//  MainTabView.swift
//  NaarsCars
//
//  Main tab-based navigation for authenticated users
//

import SwiftUI

/// Main tab view with 4 tabs for authenticated users
/// Notifications are shown as badges on relevant tabs
struct MainTabView: View {
    @StateObject private var badgeManager = BadgeCountManager.shared
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @StateObject private var reviewPromptManager = ReviewPromptManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Combined dashboard with rides and favors
            RequestsDashboardView()
                .tag(0)
                .badge(badgeManager.requestsBadgeCount > 0 ? String(badgeManager.requestsBadgeCount) : nil)
                .tabItem {
                    Label("Requests", systemImage: "car.fill")
                }
            
            ConversationsListView()
                .tag(1)
                .badge(badgeManager.messagesBadgeCount > 0 ? String(badgeManager.messagesBadgeCount) : nil)
                .tabItem {
                    Label("Messages", systemImage: "message.fill")
                }
            
            CommunityTabView()
                .tag(2)
                .badge(badgeManager.communityBadgeCount > 0 ? String(badgeManager.communityBadgeCount) : nil)
                .tabItem {
                    Label("Community", systemImage: "person.3.fill")
                }
            
            MyProfileView()
                .tag(3)
                .badge(badgeManager.profileBadgeCount > 0 ? String(badgeManager.profileBadgeCount) : nil)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .onChange(of: navigationCoordinator.selectedTab) { _, newTab in
            selectedTab = newTab.rawValue
        }
        .onChange(of: selectedTab) { oldValue, newTab in
            // Update coordinator when user manually changes tab
            if let tab = NavigationCoordinator.Tab(rawValue: newTab) {
                navigationCoordinator.selectedTab = tab
            }
            
            // Clear badges when navigating to their respective tabs
            Task {
                switch newTab {
                case 0: // Requests
                    await badgeManager.clearRequestsBadge()
                case 1: // Messages
                    await badgeManager.clearMessagesBadge()
                case 2: // Community
                    badgeManager.clearCommunityBadge()
                case 3: // Profile
                    await badgeManager.clearProfileBadge()
                default:
                    break
                }
            }
        }
        .task {
            // Refresh badges on appear
            await badgeManager.refreshAllBadges()
            // Check for review prompts
            await reviewPromptManager.checkForPendingPrompts()
        }
        .sheet(item: $reviewPromptManager.pendingPrompt) { prompt in
            ReviewPromptSheet(
                requestType: prompt.requestType,
                requestId: prompt.requestId,
                requestTitle: prompt.requestTitle,
                fulfillerId: prompt.fulfillerId,
                fulfillerName: prompt.fulfillerName,
                onReviewSubmitted: {
                    reviewPromptManager.clearPrompt()
                    // Check for next prompt
                    Task {
                        await reviewPromptManager.checkForPendingPrompts()
                    }
                },
                onReviewSkipped: {
                    reviewPromptManager.clearPrompt()
                    // Check for next prompt
                    Task {
                        await reviewPromptManager.checkForPendingPrompts()
                    }
                }
            )
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
