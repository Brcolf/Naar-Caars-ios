//
//  MainTabView.swift
//  NaarsCars
//
//  Main tab-based navigation for authenticated users
//

import SwiftUI

/// Main tab view: Requests, Messages, Town Hall and Profile, then Explore as the trailing
/// search-role tab. Notifications are shown as badges on relevant tabs
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var badgeManager = BadgeCountManager.shared
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var promptCoordinator = PromptCoordinator.shared
    @State private var toastManager = InAppToastManager.shared
    @State private var selectedTab: NavigationCoordinator.Tab = .requests
    @State private var showGuidelinesAcceptance = false
    @State private var showNotificationsSheet = false
    @State private var isNotificationsSheetVisible = false
    /// The sign-in prompt for a guest who followed an auth-required intent (its reason names the action).
    @State private var guestPromptReason: GuestRestrictionReason?
    /// A saved invite code opens My communities once per view lifetime.
    @State private var didOfferPendingInvite = false

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
            .accessibilityLabel("toast_new_message_accessibility".localized)
            .accessibilityHint("toast_new_message_hint".localized)
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    var body: some View {
        @Bindable var promptCoordinator = promptCoordinator
        TabView(selection: $selectedTab) {
            // Combined dashboard with rides and favors
            Tab("nav_tab_requests".localized, systemImage: "car.fill", value: NavigationCoordinator.Tab.requests) {
                RequestsDashboardView()
            }
            .badge(badgeManager.counts.requests)
            .accessibilityHint("nav_tab_requests_hint".localized)

            Tab("nav_tab_messages".localized, systemImage: "message.fill", value: NavigationCoordinator.Tab.messages) {
                if appState.isGuest {
                    GuestMessagesView()
                } else {
                    ConversationsListView()
                }
            }
            .badge(badgeManager.counts.messages)
            .accessibilityHint("nav_tab_messages_hint".localized)

            Tab("nav_tab_town_hall".localized, systemImage: "person.3.fill", value: NavigationCoordinator.Tab.townHall) {
                CommunityTabView()
            }
            .badge(badgeManager.counts.community)
            .accessibilityHint("nav_tab_town_hall_hint".localized)

            Tab("nav_tab_profile".localized, systemImage: "person.fill", value: NavigationCoordinator.Tab.profile) {
                if appState.isGuest {
                    GuestProfileView()
                } else {
                    MyProfileView()
                }
            }
            .accessibilityHint("nav_tab_profile_hint".localized)

            // The search-role tab: iOS draws it apart at the trailing end with a magnifying glass;
            // "Explore" is its screen title and VoiceOver name.
            Tab("explore_title".localized, systemImage: "magnifyingglass", value: NavigationCoordinator.Tab.explore, role: .search) {
                ExploreView()
            }
            .badge(appState.isGuest ? 0 : badgeManager.counts.explore)
            .accessibilityHint("explore_tab_hint".localized)
            .accessibilityIdentifier("tab.explore")
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: navigationCoordinator.selectedTab) { _, newTab in
            selectedTab = newTab
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            // Update coordinator when user manually changes tab
            navigationCoordinator.selectedTab = newTab

            // Notify RefreshCoordinator of visible domain (Profile and Explore have none)
            RefreshCoordinator.shared.setVisibleDomain(newTab.refreshDomain)

            // Tear down conversation WebSocket when leaving messaging tab
            if oldTab == .messages && newTab != .messages {
                Task { await MessagingSyncEngine.shared.cancelGracePeriodAndUnsubscribe() }
            }

            guard !appState.isGuest else { return }
            // Clear badges when navigating to their respective tabs
            Task {
                switch newTab {
                case .requests:
                    await badgeManager.clearRequestsBadge()
                case .messages:
                    await badgeManager.clearMessagesBadge()
                case .townHall:
                    await badgeManager.clearCommunityBadge(visibleCommunityId: CommunityContext.shared.communityTabId)
                case .explore:
                    await badgeManager.clearExploreBadge()
                case .profile:
                    break
                }
            }
        }
        // initial: true also applies an intent that was set before this view existed (a push
        // tapped while the app was not running, or before sign-in finished); onChange alone
        // never fires for a value that is already there.
        .onChange(of: navigationCoordinator.pendingIntent, initial: true) { oldIntent, intent in
            // Old and new are the same value only on that first pass.
            let isInitialPass = oldIntent == intent
            if isInitialPass {
                // A new MainTabView starts on its own tab while the coordinator still remembers
                // the tab of the previous one (sign-out happens on Profile). Its setter ignores
                // equal values, so bring it back in step before anything is routed.
                navigationCoordinator.selectedTab = selectedTab
            }
            guard let intent else { return }

            // Guest guard: admin-only intents are silently dropped; auth-required intents
            // show the sign-in prompt and clear the pending intent.
            if appState.isGuest {
                if navigationCoordinator.intentIsAdminOnly(intent) {
                    navigationCoordinator.pendingIntent = nil
                    return
                }
                if navigationCoordinator.intentRequiresAuth(intent) {
                    navigationCoordinator.pendingIntent = nil
                    guestPromptReason = navigationCoordinator.guestPromptReason(for: intent)
                    return
                }
            }

            if case .notifications = intent {
                showNotificationsSheet = true
                return
            }
            if isNotificationsSheetVisible {
                return
            }
            navigationCoordinator.selectedTab = intent.targetTab
            if isInitialPass {
                // On the first pass the two coordinator writes above can cancel out (remembered
                // tab equal to the target), and the onChange on the coordinator's tab would
                // then report nothing, so select the tab here as well.
                selectedTab = intent.targetTab
            }
            if case .explore = intent {
                // Only a tab selection: no screen consumes it.
                navigationCoordinator.pendingIntent = nil
            }
        }
        // initial: true so a flag raised before this view existed (review push tapped while the
        // app was not running) is cleared instead of staying latched for the whole session.
        .onChange(of: navigationCoordinator.showReviewPrompt, initial: true) { wasRaised, show in
            guard show else { return }
            // The flag is only a trigger: capture the ids and clear it straight away. It used to
            // stay true whenever no prompt could be built (already reviewed, the caller is not
            // the poster, request deleted, offline), and every later review tap was then
            // true → true, which onChange never reports.
            let rideId = navigationCoordinator.reviewPromptRideId
            let favorId = navigationCoordinator.reviewPromptFavorId
            navigationCoordinator.resetReviewPrompt()
            // Raised before this view existed (old and new are both true on the first pass):
            // `.task` below already loads every pending review prompt, and fetching this one
            // alongside it can queue the same prompt twice.
            guard !wasRaised else { return }
            AppLogger.info("app", "[MainTabView] Presenting ReviewModal (showReviewPrompt=true)")
            Task { @MainActor in
                if let userId = AuthService.shared.currentUserId {
                    if let rideId { await promptCoordinator.enqueueReviewPrompt(requestType: .ride, requestId: rideId, userId: userId) }
                    if let favorId { await promptCoordinator.enqueueReviewPrompt(requestType: .favor, requestId: favorId, userId: userId) }
                }
            }
        }
        .onChange(of: navigationCoordinator.pendingCompletionPromptFromDeferred?.1) { _, requestId in
            // Completion-reminder push tap (AppDelegate → applyNotificationIntent(.showRequestCompletion)).
            // While the notifications sheet is up, its onDismiss consumes the pending prompt instead.
            guard requestId != nil, !isNotificationsSheetVisible else { return }
            Task { @MainActor in
                await enqueuePendingCompletionPromptIfNeeded()
            }
        }
        .task {
            guard !appState.isGuest else { return }
            // Check if user needs to accept community guidelines
            checkGuidelinesAcceptance()
            // Refresh badges on appear (RefreshCoordinator is the single refresh owner)
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "mainTabAppear")
            // Check for pending prompts (completion and review)
            if let userId = AuthService.shared.currentUserId {
                await promptCoordinator.checkForPendingPrompts(userId: userId)
            }
            // A completion-reminder push tapped while the app was not running set its prompt
            // before this view existed, so the onChange above never saw it. The check above does
            // not load it either: it returns reminders that are due, and a reminder that has
            // just been sent is rescheduled. Enqueue it here, after that check, so the two
            // cannot queue the same prompt twice. (Sheet up: its onDismiss consumes it.)
            if !isNotificationsSheetVisible {
                await enqueuePendingCompletionPromptIfNeeded()
            }
            offerPendingInviteIfNeeded()
        }
        // Second trigger for the guidelines check only. On a cold launch the profile is still
        // nil when the task above runs (deferred loading fills it a moment later), so that check
        // returned early and the acceptance sheet was never shown. AppState mirrors the profile
        // when it arrives; the check itself keeps reading AuthService, which also carries the
        // acceptance once it is saved.
        .task(id: appState.currentUser?.id) {
            guard !appState.isGuest else { return }
            checkGuidelinesAcceptance()
            offerPendingInviteIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
            showGuidelinesAcceptance = false
            // Navigation left over from this session must not be replayed by the next
            // MainTabView (its first pass applies whatever the coordinator still holds), where
            // it could open a ride, favor or thread of the account that just signed out.
            navigationCoordinator.pendingIntent = nil
            navigationCoordinator.pendingCompletionPromptFromDeferred = nil
            navigationCoordinator.resetReviewPrompt()
        }
        .overlay(alignment: .top) {
            if !appState.isGuest {
                toastOverlay
            }
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
                await enqueuePendingCompletionPromptIfNeeded()
            }
        }) {
            NotificationsListView()
                .onAppear { isNotificationsSheetVisible = true }
        }
        .sheet(item: announcementsTargetBinding, onDismiss: {
            navigationCoordinator.pendingIntent = nil
        }) { target in
            // AnnouncementsView is plain content (the notifications list pushes it), so the
            // sheet supplies the stack; the view adds its own Close button when asked.
            NavigationStack {
                AnnouncementsView(scrollToNotificationId: target.scrollToNotificationId, showsCloseButton: true)
            }
        }
        .fullScreenCover(isPresented: $showGuidelinesAcceptance, onDismiss: {
            offerPendingInviteIfNeeded()
        }) {
            GuidelinesAcceptanceSheet {
                await acceptGuidelines()
            }
        }
        .fullScreenCover(item: $promptCoordinator.activePrompt, onDismiss: {
            navigationCoordinator.resetReviewPrompt()
        }) { prompt in
            switch prompt {
            case .completion(let completion):
                // The view awaits these and shows its own progress and failure alert; a failure
                // used to be logged here while the cover stayed up with no way out.
                CompletionPromptView(
                    prompt: completion,
                    onConfirm: {
                        do {
                            try await promptCoordinator.handleCompletionResponse(completed: true)
                            // The request is now completed on the server; bring the Requests
                            // list up to date (it would keep the card as "Claimed" otherwise).
                            RequestsDashboardRefresh.afterUserAction("completionPrompt")
                        } catch {
                            AppLogger.error("app", "Failed to handle completion confirm: \(error)")
                            throw error
                        }
                    },
                    onSnooze: {
                        do {
                            try await promptCoordinator.handleCompletionResponse(completed: false)
                        } catch {
                            AppLogger.error("app", "Failed to handle completion snooze: \(error)")
                            throw error
                        }
                    },
                    onClose: { promptCoordinator.dismissCompletionPromptWithoutAnswer() }
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
        .sheet(item: $guestPromptReason) { reason in
            GuestSignInPromptView(
                reason: reason,
                onSignUp: {
                    appState.isGuestMode = false
                    AppLaunchManager.shared.exitGuestMode()
                },
                onLogIn: {
                    appState.isGuestMode = false
                    AppLaunchManager.shared.exitGuestMode()
                }
            )
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
    /// Consumes `NavigationCoordinator.pendingCompletionPromptFromDeferred` (set by a completion
    /// reminder push tap) by enqueueing the Yes/No prompt through the PromptCoordinator.
    private func enqueuePendingCompletionPromptIfNeeded() async {
        guard let (requestType, requestId) = navigationCoordinator.pendingCompletionPromptFromDeferred else { return }
        navigationCoordinator.pendingCompletionPromptFromDeferred = nil
        guard let userId = AuthService.shared.currentUserId else { return }
        AppLogger.info("app", "[MainTabView] Enqueueing completion prompt requestType=\(requestType) requestId=\(requestId)")
        await promptCoordinator.enqueueCompletionPrompt(requestType: requestType, requestId: requestId, userId: userId)
    }

    /// An invite code saved on Welcome before sign-in opens My communities, whose join sheet
    /// holds the code. Never under the guidelines cover (raised from the same first `.task`): the
    /// cover's `onDismiss` calls this again. Reading the store does not clear it; only a
    /// redemption (or a dead code) does, so a sheet that is cancelled loses nothing.
    private func offerPendingInviteIfNeeded() {
        guard !didOfferPendingInvite,
              !appState.isGuest,
              !showGuidelinesAcceptance,
              AuthService.shared.currentProfile != nil,
              PendingInviteStore().peek() != nil else { return }
        didOfferPendingInvite = true
        navigationCoordinator.pendingIntent = .myCommunities
    }

    private func checkGuidelinesAcceptance() {
        guard let profile = AuthService.shared.currentProfile else { return }

        // Show guidelines if not yet accepted
        if !profile.guidelinesAccepted {
            showGuidelinesAcceptance = true
        }
    }

    /// Handle guidelines acceptance
    /// - Returns: false when the acceptance could not be saved, so the sheet can say so
    private func acceptGuidelines() async -> Bool {
        guard let userId = AuthService.shared.currentUserId else { return false }

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
            return true
        } catch {
            AppLogger.error("app", "Failed to accept guidelines: \(error)")
            // Keep the sheet open if acceptance fails
            return false
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

extension NavigationCoordinator.Tab {
    /// The domain `RefreshCoordinator.setVisibleDomain` is told about when this tab is selected.
    /// Profile and Explore have none: Explore's reads are its own, never a coordinator domain.
    var refreshDomain: RefreshCoordinator.Domain? {
        switch self {
        case .requests: return .dashboard
        case .messages: return .conversations
        case .townHall: return .townHall
        case .profile, .explore: return nil
        }
    }
}

#Preview {
    MainTabView()
}
