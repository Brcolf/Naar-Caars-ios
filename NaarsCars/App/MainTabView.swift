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
    @StateObject private var promptCoordinator = PromptCoordinator.shared
    @ObservedObject private var toastManager = InAppToastManager.shared
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showGuidelinesAcceptance = false

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = toastManager.latestToast {
            Button {
                navigationCoordinator.conversationScrollTarget = .init(
                    conversationId: toast.conversationId,
                    messageId: toast.messageId
                )
                toastManager.latestToast = nil
                navigationCoordinator.navigate(to: .conversation(id: toast.conversationId))
            } label: {
                InAppMessageToastView(toast: toast)
            }
            .buttonStyle(.plain)
            .id("app.toast.inAppMessage")
            .accessibilityLabel("New message notification")
            .accessibilityHint("Double-tap to open the conversation")
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Combined dashboard with rides and favors
            RequestsDashboardView()
                .tag(0)
                .badge(badgeManager.requestsBadgeCount > 0 ? String(badgeManager.requestsBadgeCount) : nil)
                .tabItem {
                    Label("nav_tab_requests".localized, systemImage: "car.fill")
                }
                .accessibilityHint("View ride and favor requests")
            
            ConversationsListView()
                .tag(1)
                .badge(badgeManager.messagesBadgeCount > 0 ? String(badgeManager.messagesBadgeCount) : nil)
                .tabItem {
                    Label("nav_tab_messages".localized, systemImage: "message.fill")
                }
                .accessibilityHint("View your conversations")
            
            CommunityTabView()
                .tag(2)
                .badge(badgeManager.communityBadgeCount > 0 ? String(badgeManager.communityBadgeCount) : nil)
                .tabItem {
                    Label("nav_tab_community".localized, systemImage: "person.3.fill")
                }
                .accessibilityHint("View community features")
            
            MyProfileView()
                .tag(3)
                .badge(badgeManager.profileBadgeCount > 0 ? String(badgeManager.profileBadgeCount) : nil)
                .tabItem {
                    Label("nav_tab_profile".localized, systemImage: "person.fill")
                }
                .accessibilityHint("View and edit your profile")
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
                    await badgeManager.clearCommunityBadge()
                case 3: // Profile
                    await badgeManager.clearProfileBadge()
                default:
                    break
                }
            }
        }
        .onChange(of: navigationCoordinator.showReviewPrompt) { _, show in
            guard show else { return }
            Task { @MainActor in
                if let userId = AuthService.shared.currentUserId {
                    let rideId = navigationCoordinator.reviewPromptRideId
                    let favorId = navigationCoordinator.reviewPromptFavorId
                    if let rideId { await promptCoordinator.enqueueReviewPrompt(requestType: .ride, requestId: rideId, userId: userId) }
                    if let favorId { await promptCoordinator.enqueueReviewPrompt(requestType: .favor, requestId: favorId, userId: userId) }
                }
                navigationCoordinator.resetReviewPrompt()
            }
        }
        .task {
            // Check if user needs to accept community guidelines
            checkGuidelinesAcceptance()
            // Refresh badges on appear
            await badgeManager.refreshAllBadges()
            // Check for pending prompts (completion and review)
            if let userId = AuthService.shared.currentUserId {
                await promptCoordinator.checkForPendingPrompts(userId: userId)
            }
        }
        .overlay(alignment: .top) {
            toastOverlay
        }
        .offlineBanner()
        .sheet(isPresented: $navigationCoordinator.navigateToNotifications, onDismiss: {
            navigationCoordinator.navigateToNotifications = false
        }) {
            NotificationsListView()
                .environmentObject(appState)
        }
        .sheet(item: $navigationCoordinator.announcementsNavigationTarget, onDismiss: {
            navigationCoordinator.announcementsNavigationTarget = nil
        }) { target in
            AnnouncementsView(scrollToNotificationId: target.scrollToNotificationId)
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showGuidelinesAcceptance) {
            GuidelinesAcceptanceSheet {
                await acceptGuidelines()
            }
        }
        .fullScreenCover(item: $promptCoordinator.activePrompt) { prompt in
            switch prompt {
            case .completion(let completion):
                CompletionPromptView(
                    prompt: completion,
                    onConfirm: { Task {
                        do {
                            try await promptCoordinator.handleCompletionResponse(completed: true)
                        } catch {
                            AppLogger.error("app", "Failed to handle completion confirm: \(error)")
                        }
                    } },
                    onSnooze: { Task {
                        do {
                            try await promptCoordinator.handleCompletionResponse(completed: false)
                        } catch {
                            AppLogger.error("app", "Failed to handle completion snooze: \(error)")
                        }
                    } }
                )
            case .review(let review):
                ReviewPromptSheet(
                    requestType: review.requestType.rawValue,
                    requestId: review.requestId,
                    requestTitle: review.requestTitle,
                    fulfillerId: review.fulfillerId,
                    fulfillerName: review.fulfillerName,
                    onReviewSubmitted: { Task { await promptCoordinator.finishReviewPrompt() } },
                    onReviewSkipped: { Task { await promptCoordinator.finishReviewPrompt() } }
                )
            }
        }
        .alert("nav_open_link".localized, isPresented: $navigationCoordinator.showDeepLinkConfirmation) {
            Button("nav_open".localized, role: .destructive) {
                navigationCoordinator.applyPendingDeepLink()
            }
            Button("nav_stay".localized, role: .cancel) {
                navigationCoordinator.cancelPendingDeepLink()
            }
        } message: {
            Text("nav_open_link_warning".localized)
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
            AppLogger.error("app", "Failed to accept guidelines: \(error)")
            // Keep the sheet open if acceptance fails
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
