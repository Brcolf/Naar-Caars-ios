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
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showGuidelinesAcceptance = false
    
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
                    await await await badgeManager.clearCommunityBadge()
                case 3: // Profile
                    await badgeManager.clearProfileBadge()
                default:
                    break
                }
            }
        }
        .task {
            // Check if user needs to accept community guidelines
            checkGuidelinesAcceptance()
            // Refresh badges on appear
            await badgeManager.refreshAllBadges()
            // Check for review prompts
            await reviewPromptManager.checkForPendingPrompts()
        }
        .fullScreenCover(isPresented: $showGuidelinesAcceptance) {
            GuidelinesAcceptanceSheet {
                await acceptGuidelines()
            }
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
    
    // MARK: - Helper Methods
    
    /// Check if user needs to accept community guidelines
    private func checkGuidelinesAcceptance() {
        guard let profile = appState.currentUser else { return }
        
        // Show guidelines if not yet accepted
        if !profile.guidelinesAccepted {
            showGuidelinesAcceptance = true
        }
    }
    
    /// Handle guidelines acceptance
    private func acceptGuidelines() async {
        guard let userId = appState.currentUser?.id else { return }
        
        do {
            // Update profile with guidelines acceptance
            try await ProfileService.shared.acceptCommunityGuidelines(userId: userId)
            
            // Refresh the user's profile in app state
            if let updatedProfile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                await MainActor.run {
                    appState.currentUser = updatedProfile
                }
            }
            
            // Dismiss the sheet
            await MainActor.run {
                showGuidelinesAcceptance = false
            }
        } catch {
            print("Failed to accept guidelines: \(error)")
            // Keep the sheet open if acceptance fails
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
