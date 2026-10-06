//
//  FavorDetailView.swift
//  NaarsCars
//
//  View for displaying favor details
//

import SwiftUI
import MapKit
import CoreLocation

struct FavorDetailView: View {
    let favorId: UUID
    @StateObject private var viewModel = FavorDetailViewModel()
    @StateObject private var claimViewModel = ClaimViewModel()
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var guestPromptReason: GuestRestrictionReason?
    @State private var showEditFavor = false
    @State private var showDeleteAlert = false
    @State private var showClaimSheet = false
    @State private var showUnclaimSheet = false
    @State private var showCompleteSheet = false
    @State private var showReviewSheet = false
    @State private var showPhoneRequired = false
    /// Set by PhoneRequiredSheet's "Add Phone Number"; read when that sheet has dismissed.
    @State private var showProfileFromPhoneRequired = false
    @State private var showEditProfileForPhone = false
    /// A question someone else asked, being reported.
    @State private var questionToReport: RequestQA?
    @State private var reportedQuestionIds: Set<UUID> = []
    /// Same stored choice as the ride screen (Apple Maps or Google Maps).
    @AppStorage("preferredMapsApp") private var preferredMapsApp: String = ""
    @State private var showMapsChoiceDialog = false
    @State private var selectedConversationId: UUID?
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var highlightedAnchor: RequestDetailAnchor?
    @State private var highlightTask: Task<Void, Never>?
    @State private var clearedAnchors: Set<RequestDetailAnchor> = []
    @State private var toastMessage: String? = nil
    /// A failed action (delete, for one). Shown as an error banner; these used to go through
    /// the success toast with its checkmark and success haptic.
    @State private var actionErrorMessage: String?
    @State private var showSuccess = false
    @State private var showReportSheet = false
    @State private var hasReported = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                    if let favor = viewModel.favor {
                        favorDetails(favor: favor)
                    } else if viewModel.isUnavailable {
                        // Deleted, or hidden by moderators. Reached from a stale card, an old
                        // notification or a link; there is nothing to retry, only a way back.
                        EmptyStateView(
                            icon: "questionmark.folder",
                            title: "request_unavailable_title".localized,
                            message: "request_unavailable_message".localized,
                            actionTitle: "request_unavailable_back".localized,
                            action: { dismiss() }
                        )
                    } else if viewModel.isLoading {
                        LoadingView(message: "favor_detail_loading".localized, isEmbedded: true)
                    } else if let error = viewModel.error {
                        ErrorView(
                            error: error,
                            retryAction: {
                                Task { await viewModel.loadFavor(id: favorId) }
                            }
                        )
                    }
                }
                .padding()
                .onChange(of: navigationCoordinator.pendingIntent) { _, _ in
                    handlePendingRequestNavigation(proxy: proxy)
                }
                .onAppear {
                    handlePendingRequestNavigation(proxy: proxy)
                }
            }
        }
        // Grouped ground, like Requests and Profile, so the cards read as cards.
        .background(Color.naarsBackground)
        .navigationTitle("favor_detail_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.isPoster,
               let favor = viewModel.favor,
               !appState.isGuest,
               !favor.isModerationHidden {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if hasReported {
                        // The only sign that the report went through, so it has to be legible
                        // (half-opacity secondary was about 1.7:1) and spoken.
                        Image(systemName: "flag.fill")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("townhall_reported".localized)
                    } else {
                        Button {
                            showReportSheet = true
                        } label: {
                            Image(systemName: "flag")
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("report_favor_accessibility".localized)
                    }
                }
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
        .sheet(isPresented: $showReportSheet) {
            if let favor = viewModel.favor {
                ReportContentSheet(
                    context: .favor(
                        id: favor.id,
                        authorId: favor.userId,
                        preview: favor.title
                    ),
                    onReported: { hasReported = true }
                )
            }
        }
        .sheet(item: $questionToReport) { qa in
            // The server has no report target for a question, so the report is filed against
            // the person who asked it, with the question and the favor id sent along for the
            // moderators. (Filing it against the favor would be dropped as a duplicate after
            // the first report, and acting on it would hide the poster's favor.)
            ReportContentSheet(
                context: .user(
                    id: qa.userId,
                    name: "\(qa.asker?.name ?? "common_someone".localized): \(qa.question)"
                ),
                onReported: { reportedQuestionIds.insert(qa.id) },
                contextNote: "Question on favor \(favorId.uuidString): \(qa.question)"
            )
        }
        .refreshable { await viewModel.loadFavor(id: favorId) }
        .task {
            await viewModel.loadFavor(id: favorId)
            if !(viewModel.favor?.isModerationHidden ?? false) {
                viewModel.checkCalendarOffer()
            }
        }
        .sheet(isPresented: $showEditFavor) {
            if let favor = viewModel.favor {
                EditFavorView(favor: favor) {
                    Task { await viewModel.loadFavor(id: favorId) }
                }
            }
        }
        .alert("favor_detail_delete_title".localized, isPresented: $showDeleteAlert) {
            Button("favor_detail_cancel".localized, role: .cancel) {}
            Button("favor_detail_delete".localized, role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteFavor()
                        showSuccess = true
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            // Someone has committed to this favor: say who, and that nothing tells them.
            if let favor = viewModel.favor, favor.claimedBy != nil {
                Text("favor_detail_delete_claimed_confirmation".localized(with: favor.claimer?.name ?? "common_someone".localized))
            } else {
                Text("favor_detail_delete_confirmation".localized)
            }
        }
        .alert("calendar_offer_title".localized, isPresented: $viewModel.showCalendarOffer) {
            Button("calendar_offer_add".localized) {
                Task { await viewModel.acceptCalendarOffer() }
            }
            Button("calendar_offer_not_now".localized, role: .cancel) {
                viewModel.dismissCalendarOffer()
            }
        } message: {
            // A favor with no time is added as an all-day event, which gets no 1-hour reminder.
            Text((viewModel.favor?.time ?? "").isEmpty
                 ? "calendar_offer_favor_message_all_day".localized
                 : "calendar_offer_favor_message".localized)
        }
        .sheet(isPresented: $showClaimSheet, onDismiss: {
            // Check calendar offer after sheet is fully dismissed so the alert can present
            if claimViewModel.lastClaimSucceeded {
                claimViewModel.lastClaimSucceeded = false
                viewModel.checkCalendarOffer()
            }
        }) {
            if let favor = viewModel.favor {
                ClaimSheet(
                    requestType: "favor",
                    requestTitle: favor.title,
                    onConfirm: {
                        try await claimViewModel.claim(requestType: "favor", requestId: favor.id)
                        await viewModel.loadFavor(id: favorId)
                        claimViewModel.lastClaimSucceeded = true
                    }
                )
                .id(RequestDetailAnchor.claimSheet.anchorId(for: .favor))
            }
        }
        .sheet(isPresented: $showCompleteSheet) {
            if let favor = viewModel.favor {
                CompleteSheet(
                    requestType: "favor",
                    requestTitle: favor.title,
                    onConfirm: {
                        try await claimViewModel.complete(requestType: "favor", requestId: favor.id)
                        await viewModel.loadFavor(id: favorId)
                    },
                    isPoster: viewModel.isPoster
                )
            }
        }
        .sheet(isPresented: $showUnclaimSheet) {
            if let favor = viewModel.favor {
                UnclaimSheet(
                    requestType: "favor",
                    requestTitle: favor.title,
                    onConfirm: {
                        try await claimViewModel.unclaim(requestType: "favor", requestId: favor.id)
                        await viewModel.loadFavor(id: favorId)
                    }
                )
                .id(RequestDetailAnchor.unclaimSheet.anchorId(for: .favor))
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            if let favor = viewModel.favor, let claimerId = favor.claimedBy {
                let claimerName = favor.claimer?.name ?? "favor_edit_someone".localized
                LeaveReviewView(
                    requestType: "favor",
                    requestId: favor.id,
                    requestTitle: favor.title,
                    fulfillerId: claimerId,
                    fulfillerName: claimerName,
                    onReviewSubmitted: {
                        Task { await viewModel.loadFavor(id: favorId) }
                    },
                    onReviewSkipped: {
                        Task { await viewModel.loadFavor(id: favorId) }
                    }
                )
                .id(RequestDetailAnchor.reviewSheet.anchorId(for: .favor))
            }
        }
        .sheet(isPresented: $showPhoneRequired, onDismiss: {
            // Open Edit Profile once this sheet has finished dismissing; two sheets cannot be
            // up at the same time.
            if showProfileFromPhoneRequired {
                showProfileFromPhoneRequired = false
                showEditProfileForPhone = true
            }
        }) {
            PhoneRequiredSheet(showProfileScreen: $showProfileFromPhoneRequired)
        }
        // Edit Profile as a sheet, where the phone field is. This used to push the whole
        // Profile tab (its own navigation stack, bell, Sign Out and Delete Account) into the
        // Requests stack.
        .sheet(isPresented: $showEditProfileForPhone) {
            if let profile = claimViewModel.profileForEditing {
                EditProfileView(profile: profile)
            }
        }
        .sheet(isPresented: $claimViewModel.showPushPermissionPrompt) {
            PushPermissionPromptView(
                onAllow: {
                    Task {
                        _ = await PushNotificationService.shared.requestPermission()
                    }
                },
                onNotNow: {
                    // User declined - do nothing, they can enable later in Settings
                }
            )
        }
        .navigationDestination(item: $selectedConversationId) { conversationId in
            ConversationDetailView(conversationId: conversationId)
        }
        .sheet(isPresented: $showAddParticipants) {
            if let favor = viewModel.favor {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: getExistingParticipantIds(favor: favor),
                    onDismiss: {
                        // Copy the selection before it is cleared below; the task runs after
                        // this closure returns and used to read an already-empty set.
                        let userIds = Array(selectedUserIds)
                        if !userIds.isEmpty {
                            Task {
                                let added = await viewModel.addParticipants(userIds)
                                if !added {
                                    actionErrorMessage = "request_add_participants_failed".localized
                                }
                            }
                        }
                        showAddParticipants = false
                        selectedUserIds = []
                    }
                )
            }
        }
        .toast(message: $toastMessage)
        .errorBanner(message: $actionErrorMessage)
        .successCheckmark(isShowing: $showSuccess)
        .onChange(of: showSuccess) { _, newValue in
            if !newValue {
                dismiss()
            }
        }
        .trackScreen("FavorDetail")
    }
    
    @ViewBuilder
    private func favorDetails(favor: Favor) -> some View {
        if favor.isModerationHidden {
            if viewModel.isPoster {
                hiddenFavorPlaceholder(favor: favor)
            } else {
                ErrorView(error: "moderation_content_unavailable".localized)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: Constants.Spacing.md) {
                    if let poster = favor.poster {
                        UserAvatarLink(profile: poster, size: 60)
                    }
                    
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        NaarsChip(text: favor.statusDisplayText, tint: favor.status.color, size: .large)
                            .id(RequestDetailAnchor.statusBadge.anchorId(for: .favor))
                            .requestHighlight(highlightedAnchor == .statusBadge)
                        
                        if let poster = favor.poster {
                            Text("favor_detail_requested_by".localized(with: poster.name))
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 8)
                .id(RequestDetailAnchor.mainTop.anchorId(for: .favor))
                .requestHighlight(highlightedAnchor == .mainTop)
                .onAppear { handleSectionAppeared(.mainTop) }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(favor.title)
                        .font(.naarsTitle2)
                        .foregroundColor(.primary)
                    
                    if let description = favor.description, !description.isEmpty {
                        Text(description)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    AdaptiveRow {
                        Label("favor_detail_details".localized, systemImage: "info.circle.fill")
                            .font(.naarsTitle3)
                            .foregroundColor(.favorAccent)
                            .accessibilityAddTraits(.isHeader)
                        AdaptiveRowSpacer()
                        Text("favor_detail_hold_to_copy".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.favorAccent)
                                .font(.naarsTitle3)
                                .accessibilityHidden(true)
                            AddressText(favor.location, isRedacted: appState.isGuest)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleLocationTap(favor: favor)
                        }
                        // The row opens Maps, so say so. Guests get the sign-in prompt instead
                        // and the redacted line keeps its own "address hidden" label.
                        .accessibilityAddTraits(appState.isGuest ? [] : .isButton)
                        .accessibilityHint(appState.isGuest ? "" : "accessibility_tap_to_open_maps".localized)

                        Divider()
                        
                        AdaptiveRow(alignment: .top, spacing: Constants.Spacing.md, stackedSpacing: 12) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favor.date.dateString)
                                        .font(.naarsHeadline)
                                    Text("favor_detail_date".localized)
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "calendar")
                                    .foregroundColor(.naarsPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if let time = favor.time {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        AdaptiveRow(spacing: 4, stackedSpacing: 0) {
                                            Text(Date.displayTime(fromDatabaseTime: time))
                                                .font(.naarsHeadline)
                                            let abbrev = favor.timeZone.abbreviation(for: RequestItem.favor(favor).eventTime) ?? favor.timeZone.abbreviation() ?? "PT"
                                            Text(abbrev)
                                                .font(.naarsCaption)
                                                .foregroundColor(.secondary)
                                        }
                                        Text("favor_detail_time".localized)
                                            .font(.naarsCaption)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "clock")
                                        .foregroundColor(.naarsPrimary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(favor.duration.displayText)
                                    .font(.naarsHeadline)
                                Text("favor_detail_estimated_duration".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: favor.duration.icon)
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                }
                .cardStyle()
                // The same chooser, and the same stored choice, as the ride screen's map.
                .confirmationDialog("ride_detail_open_in_maps_title".localized, isPresented: $showMapsChoiceDialog, titleVisibility: .visible) {
                    Button("ride_detail_maps_apple".localized) {
                        preferredMapsApp = PreferredMapsApp.apple.rawValue
                        openInExternalMaps(favor: favor, provider: .apple)
                    }
                    Button("ride_detail_maps_google".localized) {
                        preferredMapsApp = PreferredMapsApp.google.rawValue
                        openInExternalMaps(favor: favor, provider: .google)
                    }
                    Button("favor_detail_cancel".localized, role: .cancel) {}
                } message: {
                    Text("ride_detail_open_in_maps_message".localized)
                }

                if let participants = favor.participants, !participants.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("favor_detail_participants".localized)
                            .font(.naarsTitle3)
                            .accessibilityAddTraits(.isHeader)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Constants.Spacing.md) {
                                ForEach(participants) { participant in
                                    VStack(spacing: 6) {
                                        UserAvatarLink(profile: participant, size: 50)
                                        Text(participant.name)
                                            .font(.naarsCaption)
                                            .lineLimit(1)
                                            // 60 pt holds a letter or two at accessibility text sizes;
                                            // this row scrolls sideways, so the name runs its full width there.
                                            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 60)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .cardStyle()
                }
                
                if let claimer = favor.claimer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("favor_detail_claimed_by".localized)
                            .font(.naarsTitle3)
                            .accessibilityAddTraits(.isHeader)

                        HStack(spacing: 12) {
                            UserAvatarLink(profile: claimer, size: 50)
                            
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text(claimer.name)
                                    .font(.naarsHeadline)
                            }
                            
                            Spacer()
                        }
                    }
                    .cardStyle()
                    .id(RequestDetailAnchor.claimerCard.anchorId(for: .favor))
                    .requestHighlight(highlightedAnchor == .claimerCard)
                }

                if favor.claimedBy != nil {
                    RequestReviewSection(
                        requestType: "favor",
                        requestId: favor.id,
                        posterId: favor.userId,
                        claimerId: favor.claimedBy,
                        isCompleted: favor.status == .completed,
                        requestTitle: favor.title,
                        claimerName: favor.claimer?.name,
                        onReviewSubmitted: {
                            Task { await viewModel.loadFavor(id: favorId) }
                        }
                    )
                }

                if !(favor.requirements?.isEmpty ?? true) || !(favor.gift?.isEmpty ?? true) {
                    VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                        if let requirements = favor.requirements, !requirements.isEmpty {
                            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                                Label("favor_detail_requirements".localized, systemImage: "list.bullet.clipboard")
                                    .font(.naarsHeadline)
                                Text(requirements)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !(favor.requirements?.isEmpty ?? true) && !(favor.gift?.isEmpty ?? true) {
                            Divider()
                        }
                        
                        if let gift = favor.gift, !gift.isEmpty {
                            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                                Label("favor_detail_gift".localized, systemImage: "gift.fill")
                                    .font(.naarsHeadline)
                                    .foregroundColor(.naarsPrimary)
                                Text(gift)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                
                RequestQAView(
                    qaItems: viewModel.qaItems,
                    requestId: favor.id,
                    requestType: "favor",
                    onPostQuestion: { question in
                        if appState.isGuest {
                            guestPromptReason = .askQuestion
                            return false
                        }
                        let countBefore = viewModel.qaItems.count
                        viewModel.error = nil
                        await viewModel.postQuestion(question)
                        guard viewModel.qaItems.count > countBefore else {
                            // The request is on screen, so the view model's error is not shown
                            // anywhere else; surface it here and keep the typed question.
                            actionErrorMessage = viewModel.error ?? "common_error".localized
                            viewModel.error = nil
                            return false
                        }
                        toastMessage = "toast_question_posted".localized
                        return true
                    },
                    isClaimed: favor.claimedBy != nil,
                    onMessageParticipants: favor.claimedBy == nil ? nil : {
                        if appState.isGuest {
                            guestPromptReason = .sendMessage
                            return
                        }
                        Task {
                            // One lookup-or-create at a time (a second tap could create a
                            // second thread); the button shows progress meanwhile.
                            guard !viewModel.isOpeningConversation else { return }
                            if let conversationId = await viewModel.createConversationWithParticipants() {
                                selectedConversationId = conversationId
                            } else {
                                actionErrorMessage = "messaging_error_create_conversation".localized
                            }
                        }
                    },
                    isOpeningConversation: viewModel.isOpeningConversation,
                    currentUserId: appState.isGuest ? nil : AuthService.shared.currentUserId,
                    onReportQuestion: { qa in
                        if appState.isGuest {
                            guestPromptReason = .reportContent
                        } else {
                            questionToReport = qa
                        }
                    },
                    onDeleteQuestion: { qa in
                        let deleted = await viewModel.deleteQuestion(qa)
                        if deleted {
                            toastMessage = "toast_question_deleted".localized
                        } else {
                            actionErrorMessage = "qa_delete_question_failed".localized
                        }
                        return deleted
                    },
                    reportedQuestionIds: reportedQuestionIds
                )
                .id(RequestDetailAnchor.qaSection.anchorId(for: .favor))
                .requestHighlight(highlightedAnchor == .qaSection)
                .onAppear {
                    handleSectionAppeared(.qaSection)
                    // Back from an asker's profile, where they may just have been blocked.
                    viewModel.removeBlockedQuestions()
                }
                
                claimButtonSection(favor: favor)
                    .id(RequestDetailAnchor.claimAction.anchorId(for: .favor))
                    .requestHighlight(highlightedAnchor == .claimAction)
                    .onAppear { handleSectionAppeared(.claimAction) }
                
                if viewModel.canEditDetails {
                    addParticipantsButton(favor: favor)
                        .accessibilityIdentifier("favor.addParticipants")
                }

                // Poster only, and not on a favor that is finished: Edit goes once the favor is
                // completed, Delete once it has been fulfilled (see the view model).
                if viewModel.canEditDetails || viewModel.canDelete {
                    HStack(spacing: Constants.Spacing.md) {
                        if viewModel.canEditDetails {
                            SecondaryButton(title: "favor_detail_edit".localized) { showEditFavor = true }
                                .accessibilityIdentifier("favor.edit")
                        }
                        if viewModel.canDelete {
                            SecondaryButton(title: "favor_detail_delete".localized, isDestructive: true) { showDeleteAlert = true }
                                .accessibilityIdentifier("favor.delete")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleRequestNavigation(_ target: RequestNotificationTarget, proxy: ScrollViewProxy) {
        let scrollAnchor = target.scrollAnchor ?? target.anchor
        let scrollId = scrollAnchor.anchorId(for: .favor)
        if let highlightAnchor = target.highlightAnchor {
            highlightSection(highlightAnchor)
        }
        
        if target.scrollAnchor != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.easeInOut) {
                    proxy.scrollTo(scrollId, anchor: .top)
                }
            }
        } else {
            withAnimation(.easeInOut) {
                proxy.scrollTo(scrollId, anchor: .top)
            }
        }
        
        AppLogger.info("favors", "Deep link to \(target.anchor.rawValue)")
    }

    private func handlePendingRequestNavigation(proxy: ScrollViewProxy) {
        guard let target = navigationCoordinator.consumeRequestNavigationTarget(for: .favor, requestId: favorId) else {
            return
        }
        handleRequestNavigation(target, proxy: proxy)
    }
    
    private func highlightSection(_ anchor: RequestDetailAnchor) {
        highlightTask?.cancel()
        highlightedAnchor = anchor
        highlightTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            highlightedAnchor = nil
        }
    }
    
    private func handleSectionAppeared(_ anchor: RequestDetailAnchor) {
        guard !clearedAnchors.contains(anchor) else { return }
        if anchor == .reviewSheet { return }
        let types = RequestNotificationMapping.notificationTypes(for: anchor, requestType: .favor)
        guard !types.isEmpty else { return }
        
        // Optimistically mark as cleared to prevent redundant calls
        clearedAnchors.insert(anchor)
        
        Task {
            // Check if we actually have unread notifications of these types for this favor
            // to avoid redundant RPC calls that return 0
            let hasUnread = await viewModel.hasUnreadNotifications(of: types)
            guard hasUnread else {
                AppLogger.info("favors", "No unread \(anchor.rawValue) notifications to clear")
                return
            }

            let updated = await NotificationService.shared.markRequestScopedRead(
                requestType: "favor",
                requestId: favorId,
                notificationTypes: types
            )
            if updated > 0 {
                _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "requestSectionViewed")
            }
        }
    }
    
    @ViewBuilder
    private func addParticipantsButton(favor: Favor) -> some View {
        Button {
            showAddParticipants = true
        } label: {
            HStack {
                Image(systemName: "person.badge.plus")
                Text("favor_detail_add_participants".localized)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.naarsCardBackground)
            .foregroundColor(.primary)
            .cornerRadius(Constants.Radius.card)
        }
    }
    
    private func getExistingParticipantIds(favor: Favor) -> [UUID] {
        var ids: [UUID] = [favor.userId]
        if let claimedBy = favor.claimedBy {
            ids.append(claimedBy)
        }
        if let participants = favor.participants {
            ids.append(contentsOf: participants.map { $0.id })
        }
        return ids
    }
    
    private func handleLocationTap(favor: Favor) {
        // A guest sees "Sign in to view address" on this row. The tap used to hand the real
        // address to Maps anyway; it now asks them to sign in, as the ride map does.
        guard !appState.isGuest else {
            guestPromptReason = .viewMap
            return
        }
        // Same stored choice and first-time chooser as the ride screen. This used to open
        // Google Maps whenever it was installed, whatever had been chosen there.
        if let preferred = PreferredMapsApp(rawValue: preferredMapsApp) {
            openInExternalMaps(favor: favor, provider: preferred)
        } else {
            showMapsChoiceDialog = true
        }
    }

    private func openInExternalMaps(favor: Favor, provider: PreferredMapsApp) {
        AppLogger.info("favors", "Opening external maps for favor: \(favor.id)")
        // Escapes "&" and "+" too; `.urlQueryAllowed` left them in and cut "5th Ave & Pine St" short.
        let location = MapsLaunchCoordinator.escapedQueryValue(favor.location)
        
        // Google Maps URL Scheme
        let googleMapsUrl = URL(string: "comgooglemaps://?q=\(location)&directionsmode=driving")
        let googleMapsWebUrl = URL(string: "\(Constants.URLs.googleMapsSearch)?api=1&query=\(location)")
        
        // Apple Maps via MKMapItem
        let appleMapsOpen = {
            let geocoder = CLGeocoder()
            Task {
                do {
                    let placemarks = try await geocoder.geocodeAddressString(favor.location)
                    guard let placemark = placemarks.first else {
                        throw NSError(domain: "Maps", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not geocode address"])
                    }
                    
                    let mapItem = MKMapItem(placemark: MKPlacemark(placemark: placemark))
                    mapItem.name = favor.title
                    
                    let launchOptions = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
                    mapItem.openInMaps(launchOptions: launchOptions)
                    AppLogger.info("favors", "Opened Apple Maps via MKMapItem")
                } catch {
                    AppLogger.error("favors", "Apple Maps failed: \(error.localizedDescription)")
                    // Fallback to simple URL
                    if let url = URL(string: "https://maps.apple.com/?daddr=\(location)") {
                        await UIApplication.shared.open(url)
                    }
                }
            }
        }
        
        switch provider {
        case .google:
            // The app when it is installed, otherwise Google Maps on the web.
            if let url = googleMapsUrl, UIApplication.shared.canOpenURL(url) {
                AppLogger.info("favors", "Opening Google Maps App")
                Task { @MainActor in
                    await UIApplication.shared.open(url)
                }
            } else if let url = googleMapsWebUrl {
                AppLogger.info("favors", "Opening Google Maps on the web")
                Task { @MainActor in
                    await UIApplication.shared.open(url)
                }
            }
        case .apple:
            AppLogger.info("favors", "Attempting Apple Maps")
            appleMapsOpen()
        }
    }

    @ViewBuilder
    private func hiddenFavorPlaceholder(favor: Favor) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: Constants.Spacing.md) {
                if let poster = favor.poster {
                    UserAvatarLink(profile: poster, size: 60)
                }

                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    NaarsChip(text: favor.statusDisplayText, tint: favor.status.color, size: .large)

                    if let poster = favor.poster {
                        Text("favor_detail_requested_by".localized(with: poster.name))
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                Label("requests_hidden_title".localized, systemImage: "eye.slash")
                    .font(.naarsTitle3)
                    .foregroundColor(.secondary)

                Text("requests_hidden_body".localized)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)

                if let hiddenReason = favor.hiddenReason, !hiddenReason.isEmpty {
                    Text("moderation_hidden_reason".localized(with: hiddenReason))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            if viewModel.canDelete {
                SecondaryButton(title: "favor_detail_delete".localized, isDestructive: true) {
                    showDeleteAlert = true
                }
                .accessibilityIdentifier("favor.delete")
            }
        }
    }
    
    @ViewBuilder
    private func claimButtonSection(favor: Favor) -> some View {
        if appState.isGuest {
            PrimaryButton(title: "guest_prompt_title_claim_favor".localized) {
                guestPromptReason = .claimFavor
            }
            .accessibilityIdentifier("favor.guestClaimPrompt")
        } else {
            let authService = AuthService.shared
            let currentUserId = authService.currentUserId

            let buttonState: ClaimButtonState = {
                if viewModel.isPoster {
                    return .isPoster
                } else if favor.status == .completed {
                    return .completed
                } else if let claimedBy = favor.claimedBy {
                    return claimedBy == currentUserId ? .claimedByMe : .claimedByOther
                } else {
                    return .canClaim
                }
            }()

            // Poster or claimer of a confirmed request (the complete_request RPC accepts both).
            // Drawn first: it is the filled primary action, and the outlined Unclaim follows it.
            let canMarkComplete = favor.status == .confirmed && favor.claimedBy != nil
                && (buttonState == .claimedByMe || buttonState == .isPoster)
            if canMarkComplete, RequestItem.favor(favor).eventTime < Date() {
                PrimaryButton(title: "favor_detail_mark_complete".localized) {
                    showCompleteSheet = true
                }
                .accessibilityIdentifier("favor.markComplete")
            }

            // Two states the shared button has no wording for get a plain note instead. A
            // co-requester is on the asking side of this favor, so "I Can Help!" on their own
            // shared favor made no sense. A favor nobody claimed before it was closed must not
            // read "Completed" here any more than on its status chip.
            let neutralNote: String? = {
                if buttonState == .canClaim && viewModel.isParticipant {
                    return "request_detail_participant_notice".localized
                }
                if buttonState == .completed && favor.isExpiredUnclaimed {
                    return "request_status_expired".localized
                }
                return nil
            }()
            if let neutralNote {
                Text(neutralNote)
                    .font(.naarsHeadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.naarsDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous))
            } else {
                ClaimButton(
                    state: buttonState,
                    action: {
                        switch buttonState {
                        case .canClaim:
                            Task {
                                let canClaim = await claimViewModel.checkCanClaim()
                                if canClaim {
                                    showClaimSheet = true
                                } else {
                                    showPhoneRequired = true
                                }
                            }
                        case .claimedByMe:
                            showUnclaimSheet = true
                        default:
                            break
                        }
                    },
                    isLoading: claimViewModel.isLoading
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        FavorDetailView(favorId: UUID())
    }
}

