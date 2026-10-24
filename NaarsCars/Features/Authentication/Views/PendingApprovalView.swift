//
//  PendingApprovalView.swift
//  NaarsCars
//
//  View shown when user is waiting for admin approval
//

import SwiftUI
import UserNotifications

/// View displayed when user account is pending admin approval
struct PendingApprovalView: View {
    // Membership list and relaunch decisions
    @StateObject private var viewModel: PendingApprovalViewModel
    // Sign-out and delete-account actions, shared with the restricted and application screens
    @StateObject private var accountViewModel = BannedAccountViewModel()
    @State private var hasRequestedNotifications = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showNotificationPrompt = false
    @State private var isCheckingStatus = false
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showJoinAnother = false
    @State private var showCreate = false
    /// "<name> was archived." when this screen follows the archive of the account's last active community.
    @State private var rootNoticeMessage: String?
    /// Recorded by "Join another community" or by a page opened from Create's nearby check; acted on
    /// once that sheet is gone.
    @State private var recordedJoin: JoinResult?
    /// Recorded by Create; acted on once the sheet (and its invite step) is gone.
    @State private var createdCommunityId: UUID?
    /// The tick, Refresh and the sheets can all decide to relaunch; only the first one runs.
    @State private var didRelaunch = false

    @MainActor init(
        viewModel: @autoclosure @escaping @MainActor () -> PendingApprovalViewModel = PendingApprovalViewModel()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        // Scrolls when the content is taller than the screen (small phones, large text sizes)
        // and otherwise keeps the centred layout: the stack is at least one screen tall.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Constants.Spacing.xl) {
                    Spacer(minLength: 0)

                    // Icon
                    Image(systemName: "hourglass")
                        .font(.system(size: 80))
                        .foregroundColor(.naarsPrimary)
                        .accessibilityHidden(true)

                    // Title — reviewer-safe copy
                    Text("pending_review_title".localized)
                        .font(.naarsTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Constants.Spacing.xl)
                        .accessibilityAddTraits(.isHeader)

                    // One line per community with a pending request; today's copy when the list
                    // is empty or could not be read
                    if viewModel.pendingCommunityNames.isEmpty {
                        // Description — reviewer-safe copy
                        Text("pending_review_body".localized)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Constants.Spacing.xl)
                    } else {
                        VStack(spacing: Constants.Spacing.sm) {
                            ForEach(Array(viewModel.pendingCommunityNames.enumerated()), id: \.offset) { _, name in
                                Text("pending_waiting_for_community".localized(with: name))
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, Constants.Spacing.xl)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("pendingApproval.pendingCommunities")
                    }

                    // Notification permission prompt
                    if notificationStatus == .notDetermined && !hasRequestedNotifications {
                        notificationPromptCard
                    } else if notificationStatus == .authorized {
                        notificationEnabledBadge
                    }

                    Spacer(minLength: 0)

                    actionButtons
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Color.naarsBackground)
        .accessibilityIdentifier("pendingApproval.screen")
        .accountDeletionFlow(
            isConfirming: $showDeleteConfirmation,
            viewModel: accountViewModel,
            message: "account_delete_pre_approval_message".localized
        )
        .sheet(isPresented: $showJoinAnother, onDismiss: joinAnotherDismissed) {
            joinAnotherSheet
        }
        .sheet(isPresented: $showCreate, onDismiss: createDismissed) {
            CreateCommunityView(
                onCreated: { createdCommunityId = $0 },
                // A join on a page opened from the nearby check; Create closes and
                // `createDismissed` runs the poll, as Join another does.
                onJoinedFromNearby: { recordedJoin = $0 }
            )
        }
        .toast(message: $rootNoticeMessage)
        .task {
            if let notice = viewModel.takeRootNotice() {
                rootNoticeMessage = notice
            }
            // Check notification status on appear
            await checkNotificationStatus()
            
            // Show notification prompt after a short delay if not determined
            if notificationStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                showNotificationPrompt = true
            }
        }
        .task {
            // Polls once on appear and then on every tick, so the person moves on by themselves
            // when a community approves (or declines) them
            await startPeriodicApprovalCheck()
        }
    }

    // MARK: - Join another / Create your own

    private var joinAnotherSheet: some View {
        JoinAnotherCommunitySheet(
            membership: { viewModel.membership(for: $0) },
            onJoined: { result in
                // Recorded once the inner sheet is gone; closing this sheet runs the poll in
                // `joinAnotherDismissed`.
                recordedJoin = result
                showJoinAnother = false
            },
            onCancel: { showJoinAnother = false }
        )
    }

    /// A recorded join is checked once its sheet is gone: an instant join relaunches into the app,
    /// a request adds its community to the list.
    private func joinAnotherDismissed() {
        guard recordedJoin != nil else { return }
        recordedJoin = nil
        Task {
            if await viewModel.poll() == .relaunch { relaunchOnce() }
        }
    }

    /// The invite step shows inside the create sheet first; the relaunch waits until it is gone.
    private func createDismissed() {
        guard createdCommunityId != nil else {
            joinAnotherDismissed()
            return
        }
        createdCommunityId = nil
        recordedJoin = nil
        relaunchOnce()
    }

    /// Unstructured on purpose: this screen leaves the hierarchy when the state becomes
    /// `.checkingAuth`, which would cancel a launch awaited from this view's tasks.
    private func relaunchOnce() {
        guard !didRelaunch else { return }
        didRelaunch = true
        Task { @MainActor in await AppLaunchManager.shared.performCriticalLaunch() }
    }
    
    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: Constants.Spacing.ms) {
            // Refresh Status
            PrimaryButton(
                title: "pending_review_refresh".localized,
                action: { refreshStatus() },
                isLoading: isCheckingStatus,
                isDisabled: isCheckingStatus
            )
            .accessibilityIdentifier("pendingApproval.refresh")

            // Outcome of the last manual check; without it the button appeared to do nothing
            if let statusMessage {
                Text(statusMessage)
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pendingApproval.statusMessage")
            }

            // Join another community
            SecondaryButton(title: "pending_join_another".localized) {
                showJoinAnother = true
            }
            .accessibilityLabel("pending_join_another".localized)
            .accessibilityIdentifier("pendingApproval.joinAnother")

            // Create your own
            SecondaryButton(title: "pending_create_own".localized) {
                showCreate = true
            }
            .accessibilityLabel("pending_create_own".localized)
            .accessibilityIdentifier("pendingApproval.createOwn")

            // Contact Support
            SecondaryButton(title: "pending_review_contact_support".localized) {
                if let url = URL(string: "mailto:naarscars@gmail.com") {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityIdentifier("pendingApproval.contactSupport")

            // Sign Out
            AccountTextAction(
                title: "pending_review_sign_out".localized,
                isBusy: accountViewModel.isSigningOut
            ) {
                Task { await accountViewModel.signOut() }
            }
            .disabled(accountViewModel.isDeletingAccount)
            .accessibilityIdentifier("pendingApproval.signOut")

            // Delete Account. Low emphasis, but it has to be here: a pending user cannot
            // reach Settings, and the account already exists (Guideline 5.1.1(v)).
            AccountTextAction(
                title: "profile_delete_account".localized,
                isDestructive: true,
                isBusy: accountViewModel.isDeletingAccount
            ) {
                showDeleteConfirmation = true
            }
            .disabled(accountViewModel.isSigningOut)
            .accessibilityIdentifier("pendingApproval.deleteAccount")
        }
        .padding(.horizontal, Constants.Spacing.xl)
        .padding(.bottom, Constants.Spacing.lg)
    }

    /// Manual status check with visible feedback
    private func refreshStatus() {
        guard !isCheckingStatus else { return }
        Task {
            isCheckingStatus = true
            statusMessage = nil
            let outcome = await viewModel.poll()
            isCheckingStatus = false

            if outcome == .relaunch {
                relaunchOnce()
                return
            }

            // The check answers "not approved" for a failed request too; connectivity is the
            // only signal available here to tell the two apart. Read through the view model,
            // which has had the path monitor running since this screen appeared.
            let message = accountViewModel.isOnline
                ? "pending_review_status_still_pending".localized
                : "pending_review_status_check_failed".localized
            statusMessage = message
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    // MARK: - Notification UI Components

    private var notificationPromptCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.naarsTitle2)
                    .foregroundColor(.naarsPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("pending_approval_enable_notifications".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                    
                    Text("pending_approval_notifications_description".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: {
                Task {
                    await requestNotificationPermission()
                }
            }) {
                Text("pending_approval_enable_button".localized)
                    .font(.naarsSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.naarsPrimary)
                    .cornerRadius(Constants.Radius.sm)
            }
            .accessibilityIdentifier("pendingApproval.enableNotifications")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(Constants.Radius.card)
        .padding(.horizontal, 32)
        .opacity(showNotificationPrompt ? 1 : 0)
        .animation(.easeIn(duration: 0.3), value: showNotificationPrompt)
    }
    
    private var notificationEnabledBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.naarsSuccess)
            
            Text("pending_approval_notifications_enabled".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Notification Methods
    
    private func checkNotificationStatus() async {
        let status = await PushNotificationService.shared.checkAuthorizationStatus()
        await MainActor.run {
            notificationStatus = status
        }
    }
    
    private func requestNotificationPermission() async {
        hasRequestedNotifications = true
        
        let granted = await PushNotificationService.shared.requestPermission()
        
        await MainActor.run {
            notificationStatus = granted ? .authorized : .denied
        }
        
        // If granted and we have a user ID, register for remote notifications
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    /// True while "Join another community" or Create is on screen, or its result has not yet been
    /// acted on. Create inserts an active owner row and an instant join an active member row, so a
    /// tick in that window would relaunch underneath the sheet (taking the new community's invite
    /// step, or the join's success state, with it); the sheet's `onDismiss` drives that relaunch.
    private var isJoinOrCreateInProgress: Bool {
        showJoinAnother || showCreate || recordedJoin != nil || createdCommunityId != nil
    }

    /// Polls on appear and then every `Constants.Timing.pendingApprovalPollInterval`, without
    /// running the launch flow, until a poll decides to relaunch (an active membership, or nothing
    /// left to wait for). The relaunch starts the deferred session (sync engines, profile,
    /// communities) or routes to onboarding. Ticks are skipped while a join or create is in
    /// progress; a relaunch decided by a poll that was already running when a sheet opened waits
    /// for the next tick after the sheet is gone (the view model answers `.relaunch` again at once).
    private func startPeriodicApprovalCheck() async {
        while !Task.isCancelled {
            if !isJoinOrCreateInProgress,
               await viewModel.poll() == .relaunch,
               !isJoinOrCreateInProgress {
                relaunchOnce()
                return
            }
            try? await Task.sleep(for: .seconds(Constants.Timing.pendingApprovalPollInterval))
        }
    }
}

/// "Join another community": the search by name or place (no Use my location outside Explore),
/// the community page, and an invite code. A join made on the page or with a code is handed to
/// `onJoined` once its own sheet is gone (present-record-act-on-dismiss).
private struct JoinAnotherCommunitySheet: View {
    private struct CodeSheet: Identifiable {
        let id = UUID()
    }

    @StateObject private var search: ExploreSearchViewModel
    /// The community page opened from a search result.
    @State private var pageTarget: UUID?
    @State private var codeSheet: CodeSheet?
    /// Recorded by the invite-code sheet; handed on once it is gone.
    @State private var recordedCodeJoin: JoinResult?

    /// The person's row for a community, from the waiting screen's own read.
    let membership: (UUID) -> CommunityMembership?
    let onJoined: (JoinResult) -> Void
    let onCancel: () -> Void

    @MainActor init(
        search: @autoclosure @escaping @MainActor () -> ExploreSearchViewModel = ExploreSearchViewModel(),
        membership: @escaping (UUID) -> CommunityMembership?,
        onJoined: @escaping (JoinResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _search = StateObject(wrappedValue: search())
        self.membership = membership
        self.onJoined = onJoined
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                    CommunitySearchPanel(
                        viewModel: search,
                        isGuest: false,
                        showsUseMyLocation: false,
                        membership: membership,
                        onSelect: { pageTarget = $0 }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pendingApproval.joinAnother.search")

                    inviteCodeCard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.naarsBackground)
            .navigationTitle("pending_join_another".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized, action: onCancel)
                        .accessibilityIdentifier("pendingApproval.joinAnother.cancel")
                }
            }
            .navigationDestination(item: $pageTarget) { communityId in
                CommunityPageView(communityId: communityId, onJoined: onJoined)
                    .id(communityId)
            }
            .sheet(item: $codeSheet, onDismiss: codeSheetDismissed) { _ in
                JoinCommunitySheet(target: .code(prefilled: nil)) { result in
                    recordedCodeJoin = result
                }
            }
        }
    }

    private var inviteCodeCard: some View {
        Button {
            codeSheet = CodeSheet()
        } label: {
            HStack(spacing: Constants.Spacing.md) {
                Image(systemName: "key.fill")
                    .foregroundColor(.naarsPrimary)
                    .accessibilityHidden(true)
                Text("explore_have_invite_code".localized)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.naarsCaption)
                    .foregroundColor(.naarsTextSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("explore_have_invite_code".localized)
        .accessibilityIdentifier("pendingApproval.joinAnother.inviteCode")
    }

    private func codeSheetDismissed() {
        guard let result = recordedCodeJoin else { return }
        recordedCodeJoin = nil
        onJoined(result)
    }
}

#if DEBUG
#Preview("Generic copy") {
    let service = PreviewCommunityService()
    service.memberships = []
    return PendingApprovalView(
        viewModel: PendingApprovalViewModel(
            service: service,
            accountRoute: { .pendingApproval },
            approvalCheck: { false }
        )
    )
}

#Preview("Two pending communities") {
    let service = PreviewCommunityService()
    service.memberships = [
        PreviewCommunityService.membership(name: "Ballard Neighbors", status: .pending),
        PreviewCommunityService.membership(name: "Fremont Families", status: .pending)
    ]
    return PendingApprovalView(
        viewModel: PendingApprovalViewModel(
            service: service,
            accountRoute: { .pendingApproval },
            approvalCheck: { false }
        )
    )
}

#Preview("Join another community") {
    let service = PreviewCommunityService()
    let search = ExploreSearchViewModel(
        service: service,
        geocoder: PreviewPlaceGeocoder(),
        locator: PreviewLocator(),
        debounce: .zero
    )
    search.query = "Ballard"
    let waiting = PreviewCommunityService.sampleSearchResults.first?.id
    return JoinAnotherCommunitySheet(
        search: search,
        membership: { id in
            id == waiting ? PreviewCommunityService.membership(name: "Ballard Neighbors", status: .pending) : nil
        },
        onJoined: { _ in },
        onCancel: {}
    )
    .environment(AppState())
}
#endif
