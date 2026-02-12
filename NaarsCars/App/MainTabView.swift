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
    @State private var isNotificationsSheetVisible = false

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = toastManager.latestToast {
            Button {
                navigationCoordinator.pendingIntent = .conversation(
                    toast.conversationId,
                    scrollTarget: .init(
                        conversationId: toast.conversationId,
                        messageId: toast.messageId
                    )
                )
                toastManager.latestToast = nil
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
        .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
            guard let intent else { return }
            if case .notifications = intent {
                return
            }
            if isNotificationsSheetVisible {
                return
            }
            navigationCoordinator.selectedTab = intent.targetTab
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
        .onChange(of: appState.currentUser?.id) { _, newUserId in
            if newUserId == nil {
                showGuidelinesAcceptance = false
                return
            }
            checkGuidelinesAcceptance()
        }
        .overlay(alignment: .top) {
            toastOverlay
        }
        .offlineBanner()
        .sheet(isPresented: notificationsSheetBinding, onDismiss: {
            isNotificationsSheetVisible = false
            navigationCoordinator.applyDeferredIntentAfterNotificationsDismissal()
        }) {
            NotificationsListView()
                .environmentObject(appState)
                .onAppear { isNotificationsSheetVisible = true }
        }
        .sheet(item: announcementsTargetBinding, onDismiss: {
            navigationCoordinator.pendingIntent = nil
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

    private var notificationsSheetBinding: Binding<Bool> {
        Binding(
            get: {
                if case .notifications = navigationCoordinator.pendingIntent {
                    return true
                }
                return false
            },
            set: { isPresented in
                guard !isPresented else { return }
                if case .notifications = navigationCoordinator.pendingIntent {
                    navigationCoordinator.pendingIntent = nil
                }
            }
        )
    }

    private var announcementsTargetBinding: Binding<NavigationCoordinator.AnnouncementsNavigationTarget?> {
        Binding(
            get: {
                guard case .announcements(let scrollId) = navigationCoordinator.pendingIntent else {
                    return nil
                }
                return .init(id: UUID(), scrollToNotificationId: scrollId)
            },
            set: { value in
                if value == nil, case .announcements = navigationCoordinator.pendingIntent {
                    navigationCoordinator.pendingIntent = nil
                }
            }
        )
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
