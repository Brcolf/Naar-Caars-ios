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
    @State private var badgeManager = BadgeCountManager.shared
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var promptCoordinator = PromptCoordinator.shared
    @State private var toastManager = InAppToastManager.shared
    @State private var selectedTab = 0
    @State private var showGuidelinesAcceptance = false
    @State private var showNotificationsSheet = false
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
        @Bindable var promptCoordinator = promptCoordinator
        TabView(selection: $selectedTab) {
            // Combined dashboard with rides and favors
            RequestsDashboardView()
                .tag(0)
                .badge(badgeManager.counts.requests > 0 ? String(badgeManager.counts.requests) : nil)
                .tabItem {
                    Label("nav_tab_requests".localized, systemImage: "car.fill")
                }
                .accessibilityHint("View ride and favor requests")
            
            ConversationsListView()
                .tag(1)
                .badge(badgeManager.counts.messages > 0 ? String(badgeManager.counts.messages) : nil)
                .tabItem {
                    Label("nav_tab_messages".localized, systemImage: "message.fill")
                }
                .accessibilityHint("View your conversations")
            
            CommunityTabView()
                .tag(2)
                .badge(badgeManager.counts.community > 0 ? String(badgeManager.counts.community) : nil)
                .tabItem {
                    Label("nav_tab_community".localized, systemImage: "person.3.fill")
                }
                .accessibilityHint("View community features")
            
            MyProfileView()
                .tag(3)
                .badge(badgeManager.counts.profile > 0 ? String(badgeManager.counts.profile) : nil)
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
                showNotificationsSheet = true
                return
            }
            if isNotificationsSheetVisible {
                return
            }
            navigationCoordinator.selectedTab = intent.targetTab
        }
        .onChange(of: navigationCoordinator.showReviewPrompt) { _, show in
            guard show else { return }
            AppLogger.info("app", "[MainTabView] Presenting ReviewModal (showReviewPrompt=true)")
            Task { @MainActor in
                if let userId = AuthService.shared.currentUserId {
                    let rideId = navigationCoordinator.reviewPromptRideId
                    let favorId = navigationCoordinator.reviewPromptFavorId
                    if let rideId { await promptCoordinator.enqueueReviewPrompt(requestType: .ride, requestId: rideId, userId: userId) }
                    if let favorId { await promptCoordinator.enqueueReviewPrompt(requestType: .favor, requestId: favorId, userId: userId) }
                }
                // Do not clear here; clear when review sheet dismisses (onReviewSubmitted/onReviewSkipped).
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
        .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
            showGuidelinesAcceptance = false
        }
        .overlay(alignment: .top) {
            toastOverlay
        }
        .offlineBanner()
        .sheet(isPresented: $showNotificationsSheet, onDismiss: {
            isNotificationsSheetVisible = false
            // Clear the pending intent now that the sheet has been dismissed
            if case .notifications = navigationCoordinator.pendingIntent {
                navigationCoordinator.pendingIntent = nil
            }
            AppLogger.info("app", "[MainTabView] Notifications sheet onDismiss — applying deferred intent")
            Task { @MainActor in
                await Task.yield()
                navigationCoordinator.applyDeferredNotificationIntentIfNeeded()
                if let (requestType, requestId) = navigationCoordinator.pendingCompletionPromptFromDeferred {
                    navigationCoordinator.pendingCompletionPromptFromDeferred = nil
                    if let userId = AuthService.shared.currentUserId {
                        AppLogger.info("app", "[MainTabView] Enqueueing completion prompt after sheet dismiss requestType=\(requestType) requestId=\(requestId)")
                        await promptCoordinator.enqueueCompletionPrompt(requestType: requestType, requestId: requestId, userId: userId)
                    }
                }
            }
        }) {
            NotificationsListView()
                .onAppear { isNotificationsSheetVisible = true }
        }
        .sheet(item: announcementsTargetBinding, onDismiss: {
            navigationCoordinator.pendingIntent = nil
        }) { target in
            AnnouncementsView(scrollToNotificationId: target.scrollToNotificationId)
        }
        .fullScreenCover(isPresented: $showGuidelinesAcceptance) {
            GuidelinesAcceptanceSheet {
                await acceptGuidelines()
            }
        }
        .fullScreenCover(item: $promptCoordinator.activePrompt, onDismiss: {
            navigationCoordinator.resetReviewPrompt()
        }) { prompt in
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
                    onReviewSubmitted: {
                        Task {
                            await promptCoordinator.finishReviewPrompt()
                            navigationCoordinator.resetReviewPrompt()
                        }
                    },
                    onReviewSkipped: {
                        Task {
                            await promptCoordinator.finishReviewPrompt()
                            navigationCoordinator.resetReviewPrompt()
                        }
                    }
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
        guard let profile = AuthService.shared.currentProfile else { return }

        // Show guidelines if not yet accepted
        if !profile.guidelinesAccepted {
            showGuidelinesAcceptance = true
        }
    }

    /// Handle guidelines acceptance
    private func acceptGuidelines() async {
        guard let userId = AuthService.shared.currentUserId else { return }

        do {
            // Update profile with guidelines acceptance
            try await ProfileService.shared.acceptCommunityGuidelines(userId: userId)

            // Refresh the cached profile so subsequent checks see the update
            if let updatedProfile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                AuthService.shared.currentProfile = updatedProfile
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

    private var announcementsTargetBinding: Binding<NavigationCoordinator.AnnouncementsNavigationTarget?> {
        Binding(
            get: {
                guard case .announcements(let scrollId) = navigationCoordinator.pendingIntent else {
                    return nil
                }
                return .init(id: scrollId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, scrollToNotificationId: scrollId)
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
}
