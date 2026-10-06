//
//  RideDetailView.swift
//  NaarsCars
//
//  View for displaying ride details
//

import SwiftUI
import MapKit

/// View for displaying ride details
struct RideDetailView: View {
    let rideId: UUID
    @StateObject private var viewModel = RideDetailViewModel()
    @StateObject private var claimViewModel = ClaimViewModel()
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var guestPromptReason: GuestRestrictionReason?
    @State private var showEditRide = false
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
    /// The map found no route between the two addresses; the savings estimate is hidden.
    @State private var routeUnavailable = false
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
    @State private var isOpeningMaps = false
    @State private var openMapsTask: Task<Void, Never>?
    @State private var openMapsLocationProvider: CurrentLocationProvider?
    @AppStorage("preferredMapsApp") private var preferredMapsApp: String = ""
    @State private var showMapsChoiceDialog = false
    @State private var showReportSheet = false
    @State private var hasReported = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                    if let ride = viewModel.ride {
                        rideDetails(ride: ride)
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
                        LoadingView(message: "ride_detail_loading".localized, isEmbedded: true)
                    } else if let error = viewModel.error {
                        ErrorView(
                            error: error,
                            retryAction: {
                                Task { await viewModel.loadRide(id: rideId) }
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
        .navigationTitle("ride_detail_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.isPoster,
               let ride = viewModel.ride,
               !appState.isGuest,
               !ride.isModerationHidden {
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
                        .accessibilityLabel("report_ride_accessibility".localized)
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
            if let ride = viewModel.ride {
                ReportContentSheet(
                    context: .ride(
                        id: ride.id,
                        authorId: ride.userId,
                        preview: "\(ride.pickup) → \(ride.destination)"
                    ),
                    onReported: { hasReported = true }
                )
            }
        }
        .sheet(item: $questionToReport) { qa in
            // The server has no report target for a question, so the report is filed against
            // the person who asked it, with the question and the ride id sent along for the
            // moderators. (Filing it against the ride would be dropped as a duplicate after
            // the first report, and acting on it would hide the poster's ride.)
            ReportContentSheet(
                context: .user(
                    id: qa.userId,
                    name: "\(qa.asker?.name ?? "common_someone".localized): \(qa.question)"
                ),
                onReported: { reportedQuestionIds.insert(qa.id) },
                contextNote: "Question on ride \(rideId.uuidString): \(qa.question)"
            )
        }
        .refreshable { await viewModel.loadRide(id: rideId) }
        .task {
            await viewModel.loadRide(id: rideId)
            if !(viewModel.ride?.isModerationHidden ?? false) {
                viewModel.checkCalendarOffer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rideFlightEnrichmentDidComplete)) { notification in
            guard let s = notification.userInfo?[RideFlightEnrichmentNotification.rideIdKey] as? String,
                  let id = UUID(uuidString: s), id == rideId else { return }
            Task { await viewModel.loadRide(id: rideId) }
        }
        .onDisappear {
            openMapsTask?.cancel()
            openMapsLocationProvider?.stop()
            openMapsTask = nil
            openMapsLocationProvider = nil
        }
        .sheet(isPresented: $showEditRide) {
            if let ride = viewModel.ride {
                EditRideView(ride: ride) {
                    Task { await viewModel.loadRide(id: rideId) }
                }
            }
        }
        .alert("ride_detail_delete_title".localized, isPresented: $showDeleteAlert) {
            Button("ride_detail_cancel".localized, role: .cancel) {}
            Button("ride_detail_delete".localized, role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteRide()
                        showSuccess = true
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            // Someone has committed to this ride: say who, and that nothing tells them.
            if let ride = viewModel.ride, ride.claimedBy != nil {
                Text("ride_detail_delete_claimed_confirmation".localized(with: ride.claimer?.name ?? "common_someone".localized))
            } else {
                Text("ride_detail_delete_confirmation".localized)
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
            Text("calendar_offer_ride_message".localized)
        }
        .sheet(isPresented: $showClaimSheet, onDismiss: {
            // Check calendar offer after sheet is fully dismissed so the alert can present
            if claimViewModel.lastClaimSucceeded {
                claimViewModel.lastClaimSucceeded = false
                viewModel.checkCalendarOffer()
            }
        }) {
            if let ride = viewModel.ride {
                ClaimSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        try await claimViewModel.claim(requestType: "ride", requestId: ride.id)
                        await viewModel.loadRide(id: rideId)
                        claimViewModel.lastClaimSucceeded = true
                    }
                )
                .id(RequestDetailAnchor.claimSheet.anchorId(for: .ride))
            }
        }
        .sheet(isPresented: $showCompleteSheet) {
            if let ride = viewModel.ride {
                CompleteSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        try await claimViewModel.complete(requestType: "ride", requestId: ride.id)
                        await viewModel.loadRide(id: rideId)
                    },
                    isPoster: viewModel.isPoster
                )
            }
        }
        .sheet(isPresented: $showUnclaimSheet) {
            if let ride = viewModel.ride {
                UnclaimSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        try await claimViewModel.unclaim(requestType: "ride", requestId: ride.id)
                        await viewModel.loadRide(id: rideId)
                    }
                )
                .id(RequestDetailAnchor.unclaimSheet.anchorId(for: .ride))
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            if let ride = viewModel.ride, let claimerId = ride.claimedBy {
                let claimerName = ride.claimer?.name ?? "common_someone".localized
                LeaveReviewView(
                    requestType: "ride",
                    requestId: ride.id,
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    fulfillerId: claimerId,
                    fulfillerName: claimerName,
                    onReviewSubmitted: {
                        Task { await viewModel.loadRide(id: rideId) }
                    },
                    onReviewSkipped: {
                        Task { await viewModel.loadRide(id: rideId) }
                    }
                )
                .id(RequestDetailAnchor.reviewSheet.anchorId(for: .ride))
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
            if let ride = viewModel.ride {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: getExistingParticipantIds(ride: ride),
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
        .trackScreen("RideDetail")
    }
    
    @ViewBuilder
    private func rideDetails(ride: Ride) -> some View {
        if ride.isModerationHidden {
            if viewModel.isPoster {
                hiddenRidePlaceholder(ride: ride)
            } else {
                ErrorView(error: "moderation_content_unavailable".localized)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section: Status and Poster
                HStack(alignment: .center, spacing: Constants.Spacing.md) {
                    if let poster = ride.poster {
                        UserAvatarLink(profile: poster, size: 60)
                    }
                    
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        NaarsChip(text: ride.statusDisplayText, tint: ride.status.color, size: .large)
                            .id(RequestDetailAnchor.statusBadge.anchorId(for: .ride))
                            .requestHighlight(highlightedAnchor == .statusBadge)
                        
                        if let poster = ride.poster {
                            Text("ride_detail_requested_by".localized(with: poster.name))
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 8)
                .id(RequestDetailAnchor.mainTop.anchorId(for: .ride))
                .requestHighlight(highlightedAnchor == .mainTop)
                .onAppear { handleSectionAppeared(.mainTop) }
                
                // Route Card
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    AdaptiveRow {
                        Label("ride_detail_route".localized, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.naarsTitle3)
                            .foregroundColor(.rideAccent)
                            .accessibilityAddTraits(.isHeader)
                        AdaptiveRowSpacer()
                        Text("ride_detail_hold_to_copy".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Constants.Spacing.md) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.naarsSuccess)
                                .font(.naarsCaption)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text("ride_detail_pickup_label".localized)
                                    .font(.naarsCaption).fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                AddressText(ride.pickup, isRedacted: appState.isGuest)
                            }
                        }

                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 20)
                            .padding(.leading, 29)

                        HStack(spacing: Constants.Spacing.md) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.rideAccent)
                                .font(.naarsTitle3)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text("ride_detail_destination_label".localized)
                                    .font(.naarsCaption).fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                AddressText(ride.destination, isRedacted: appState.isGuest)
                            }
                        }
                    }
                    
                    // No estimate for a ride the map cannot route: the saved figure is then only
                    // the minimum fare, shown beside "Could not calculate route".
                    if let estimatedCost = ride.estimatedCost, !routeUnavailable {
                        Divider()
                        // Side by side, the label breaks mid-word ("Esti-mat-ed") and the amount wraps
                        // at accessibility sizes; stack them instead.
                        let savingsLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout())
                        savingsLayout {
                            Label("ride_detail_estimated_savings".localized, systemImage: "dollarsign.circle.fill")
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer()
                            }
                            Text(RideCostEstimator.formatCost(estimatedCost))
                                .font(.naarsHeadline)
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                }
                .cardStyle()
                
                // Map Section
                VStack(alignment: .leading, spacing: 12) {
                    AdaptiveRow {
                        Label("ride_detail_route_map".localized, systemImage: "map.fill")
                            .font(.naarsTitle3)
                            .accessibilityAddTraits(.isHeader)
                        AdaptiveRowSpacer()
                        if isOpeningMaps {
                            Text("ride_detail_opening_maps".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        } else if !appState.isGuest {
                            // A real button with the same caption. Opening directions was only a
                            // tap / long-press gesture on the map, which gives VoiceOver, Voice
                            // Control and Switch Control nothing named to activate.
                            Button {
                                handleMapTap(ride: ride)
                            } label: {
                                Text("ride_detail_tap_open_maps".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("ride_detail_open_in_maps_title".localized)
                            .accessibilityAction(named: Text("ride_detail_choose_maps_app".localized)) {
                                showMapsChoiceDialog = true
                            }
                            .accessibilityIdentifier("ride.openInMaps")
                        }
                    }

                    if appState.isGuest {
                        VStack(spacing: 12) {
                            Image(systemName: "map")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("guest_map_hidden".localized)
                                .font(.naarsSubheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        // A block inside the card: the inset fill. The plain secondary system
                        // background is the card's own color in dark mode.
                        .background(Color.naarsInsetBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.sm))
                    } else {
                        RouteMapView(
                            pickup: ride.pickup,
                            destination: ride.destination,
                            onRouteResolved: { hasRoute in routeUnavailable = !hasRoute }
                        )
                            .contentShape(Rectangle())
                            .overlay(isOpeningMaps ? Color.black.opacity(0.15) : nil)
                            .allowsHitTesting(!isOpeningMaps)
                            .onTapGesture {
                                handleMapTap(ride: ride)
                            }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                showMapsChoiceDialog = true
                            }
                            .accessibilityHint("ride_detail_map_open_maps_hint".localized)
                    }
                }
                .cardStyle()
                .confirmationDialog("ride_detail_open_in_maps_title".localized, isPresented: $showMapsChoiceDialog, titleVisibility: .visible) {
                    Button("ride_detail_maps_apple".localized) {
                        preferredMapsApp = PreferredMapsApp.apple.rawValue
                        openInExternalMaps(ride: ride, provider: .apple)
                    }
                    Button("ride_detail_maps_google".localized) {
                        preferredMapsApp = PreferredMapsApp.google.rawValue
                        openInExternalMaps(ride: ride, provider: .google)
                    }
                    Button("ride_detail_cancel".localized, role: .cancel) {}
                } message: {
                    Text("ride_detail_open_in_maps_message".localized)
                }
                
                // Time and Seats Info (two columns; one column at accessibility sizes)
                AdaptiveRow(alignment: .top, spacing: Constants.Spacing.md, stackedSpacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.date.dateString)
                                    .font(.naarsHeadline)
                                Text("ride_detail_date".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar")
                                .foregroundColor(.naarsPrimary)
                        }
                        
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                AdaptiveRow(spacing: 4, stackedSpacing: 0) {
                                    Text(Date.displayTime(fromDatabaseTime: ride.time))
                                        .font(.naarsHeadline)
                                    let abbrev = ride.timeZone.abbreviation(for: RequestItem.ride(ride).eventTime) ?? ride.timeZone.abbreviation() ?? "PT"
                                    Text(abbrev)
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                                Text("ride_detail_time".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "clock")
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ride.seatsDisplayText)
                                    .font(.naarsHeadline)
                                Text("ride_detail_requested".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.naarsPrimary)
                        }
                        
                        Spacer().frame(height: 34)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardStyle()
                
                if let participants = ride.participants, !participants.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ride_detail_participants".localized)
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
                
                if let claimer = ride.claimer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ride_detail_claimed_by".localized)
                            .font(.naarsTitle3)
                            .accessibilityAddTraits(.isHeader)

                        HStack(spacing: 12) {
                            UserAvatarLink(profile: claimer, size: 50)
                            
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text(claimer.name)
                                    .font(.naarsHeadline)
                                if let car = claimer.car, !car.isEmpty {
                                    Label(car, systemImage: "car.fill")
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    .cardStyle()
                    .id(RequestDetailAnchor.claimerCard.anchorId(for: .ride))
                    .requestHighlight(highlightedAnchor == .claimerCard)
                }

                if ride.claimedBy != nil {
                    RequestReviewSection(
                        requestType: "ride",
                        requestId: ride.id,
                        posterId: ride.userId,
                        claimerId: ride.claimedBy,
                        isCompleted: ride.status == .completed,
                        requestTitle: "\(ride.pickup) → \(ride.destination)",
                        claimerName: ride.claimer?.name,
                        onReviewSubmitted: {
                            Task { await viewModel.loadRide(id: rideId) }
                        }
                    )
                }

                if let flightInfo = FlightInfo.displayInfo(for: ride) {
                    FlightRowView(flightInfo: flightInfo, style: .detail)
                        .cardStyle()
                }
                
                if !(ride.notes?.isEmpty ?? true) || !(ride.gift?.isEmpty ?? true) {
                    VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                        if let notes = ride.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                                Label("ride_detail_notes".localized, systemImage: "note.text")
                                    .font(.naarsHeadline)
                                Text(notes)
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !(ride.notes?.isEmpty ?? true) && !(ride.gift?.isEmpty ?? true) {
                            Divider()
                        }
                        
                        if let gift = ride.gift, !gift.isEmpty {
                            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                                Label("ride_detail_gift".localized, systemImage: "gift.fill")
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
                    requestId: ride.id,
                    requestType: "ride",
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
                    isClaimed: ride.claimedBy != nil,
                    onMessageParticipants: ride.claimedBy == nil ? nil : {
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
                .id(RequestDetailAnchor.qaSection.anchorId(for: .ride))
                .requestHighlight(highlightedAnchor == .qaSection)
                .onAppear {
                    handleSectionAppeared(.qaSection)
                    // Back from an asker's profile, where they may just have been blocked.
                    viewModel.removeBlockedQuestions()
                }
                
                claimButtonSection(ride: ride)
                    .id(RequestDetailAnchor.claimAction.anchorId(for: .ride))
                    .requestHighlight(highlightedAnchor == .claimAction)
                    .onAppear { handleSectionAppeared(.claimAction) }
                
                if viewModel.canEditDetails {
                    addParticipantsButton(ride: ride)
                        .accessibilityIdentifier("ride.addParticipants")
                }
                
                // Poster only, and not on a ride that is finished: Edit goes once the ride is
                // completed, Delete once it has been fulfilled (see the view model).
                if viewModel.canEditDetails || viewModel.canDelete {
                    HStack(spacing: Constants.Spacing.md) {
                        if viewModel.canEditDetails {
                            SecondaryButton(title: "ride_detail_edit".localized) { showEditRide = true }
                                .accessibilityIdentifier("ride.edit")
                        }
                        if viewModel.canDelete {
                            SecondaryButton(title: "ride_detail_delete".localized, isDestructive: true) { showDeleteAlert = true }
                                .accessibilityIdentifier("ride.delete")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleRequestNavigation(_ target: RequestNotificationTarget, proxy: ScrollViewProxy) {
        let scrollAnchor = target.scrollAnchor ?? target.anchor
        let scrollId = scrollAnchor.anchorId(for: .ride)
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
        
        AppLogger.info("rides", "[RideDetailView] Deep link to \(target.anchor.rawValue)")
    }

    private func handlePendingRequestNavigation(proxy: ScrollViewProxy) {
        guard let target = navigationCoordinator.consumeRequestNavigationTarget(for: .ride, requestId: rideId) else {
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
        let types = RequestNotificationMapping.notificationTypes(for: anchor, requestType: .ride)
        guard !types.isEmpty else { return }
        
        // Optimistically mark as cleared to prevent redundant calls
        clearedAnchors.insert(anchor)
        
        Task {
            // Check if we actually have unread notifications of these types for this ride
            // to avoid redundant RPC calls that return 0
            let hasUnread = await viewModel.hasUnreadNotifications(of: types)
            guard hasUnread else {
                AppLogger.info("rides", "[RideDetailView] No unread \(anchor.rawValue) notifications to clear")
                return
            }

            let updated = await NotificationService.shared.markRequestScopedRead(
                requestType: "ride",
                requestId: rideId,
                notificationTypes: types
            )
            if updated > 0 {
                _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "requestSectionViewed")
            }
        }
    }
    
    @ViewBuilder
    private func addParticipantsButton(ride: Ride) -> some View {
        Button {
            showAddParticipants = true
        } label: {
            HStack {
                Image(systemName: "person.badge.plus")
                Text("ride_detail_add_participants".localized)
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
    
    private func getExistingParticipantIds(ride: Ride) -> [UUID] {
        var ids: [UUID] = [ride.userId]
        if let claimedBy = ride.claimedBy { ids.append(claimedBy) }
        if let participants = ride.participants {
            ids.append(contentsOf: participants.map { $0.id })
        }
        return ids
    }
    
    private func handleMapTap(ride: Ride) {
        AppLogger.info("rides", "[RideMapTap] tapped rideId=\(ride.id)")
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        if let preferred = PreferredMapsApp(rawValue: preferredMapsApp) {
            openInExternalMaps(ride: ride, provider: preferred)
        } else {
            showMapsChoiceDialog = true
        }
    }

    private func openInExternalMaps(ride: Ride, provider: PreferredMapsApp) {
        isOpeningMaps = true
        let locationProvider = CurrentLocationProvider()
        openMapsLocationProvider = locationProvider
        openMapsTask = Task {
            await openInExternalMapsAsync(ride: ride, locationProvider: locationProvider, mapsProvider: provider)
            await MainActor.run {
                isOpeningMaps = false
                openMapsTask = nil
                openMapsLocationProvider = nil
            }
        }
    }

    private func openInExternalMapsAsync(ride: Ride, locationProvider: CurrentLocationProvider, mapsProvider: PreferredMapsApp) async {
        await withTaskCancellationHandler {
            AppLogger.info("rides", "[RideMapTap] requesting current location...")
            async let currentCoordResult = withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
                locationProvider.requestCurrentLocation(timeout: Constants.Maps.locationRequestTimeout) { coord in
                    cont.resume(returning: coord)
                }
            }
            async let pickupTask = MapService.shared.geocode(address: ride.pickup)
            async let dropoffTask = MapService.shared.geocode(address: ride.destination)

            let currentCoord = await currentCoordResult
            if Task.isCancelled { return }
            if let c = currentCoord {
                AppLogger.info("rides", "[RideMapTap] got current location lat/lon=\(c.latitude),\(c.longitude)")
            }
            let pickupCoord = try? await pickupTask
            let dropoffCoord = try? await dropoffTask
            if Task.isCancelled { return }
            await MainActor.run {
                switch mapsProvider {
                case .apple:
                    MapsLaunchCoordinator.openAppleMaps(
                        rideId: ride.id,
                        pickupCoord: pickupCoord,
                        dropoffCoord: dropoffCoord,
                        currentCoord: currentCoord,
                        pickupAddress: ride.pickup,
                        dropoffAddress: ride.destination
                    )
                case .google:
                    MapsLaunchCoordinator.openGoogleMaps(
                        rideId: ride.id,
                        pickupCoord: pickupCoord,
                        dropoffCoord: dropoffCoord,
                        currentCoord: currentCoord,
                        pickupAddress: ride.pickup,
                        dropoffAddress: ride.destination
                    )
                }
            }
        } onCancel: {
            locationProvider.stop()
        }
    }

    @ViewBuilder
    private func hiddenRidePlaceholder(ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: Constants.Spacing.md) {
                if let poster = ride.poster {
                    UserAvatarLink(profile: poster, size: 60)
                }

                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    NaarsChip(text: ride.statusDisplayText, tint: ride.status.color, size: .large)

                    if let poster = ride.poster {
                        Text("ride_detail_requested_by".localized(with: poster.name))
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

                if let hiddenReason = ride.hiddenReason, !hiddenReason.isEmpty {
                    Text("moderation_hidden_reason".localized(with: hiddenReason))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            if viewModel.canDelete {
                SecondaryButton(title: "ride_detail_delete".localized, isDestructive: true) {
                    showDeleteAlert = true
                }
                .accessibilityIdentifier("ride.delete")
            }
        }
    }
    
    @ViewBuilder
    private func claimButtonSection(ride: Ride) -> some View {
        if appState.isGuest {
            PrimaryButton(title: "guest_prompt_title_claim_ride".localized) {
                guestPromptReason = .claimRide
            }
            .accessibilityIdentifier("ride.guestClaimPrompt")
        } else {
            let authService = AuthService.shared
            let currentUserId = authService.currentUserId

            let buttonState: ClaimButtonState = {
                if viewModel.isPoster {
                    return .isPoster
                } else if ride.status == .completed {
                    return .completed
                } else if let claimedBy = ride.claimedBy {
                    return claimedBy == currentUserId ? .claimedByMe : .claimedByOther
                } else {
                    return .canClaim
                }
            }()

            // Completion used to be reachable only from the reminder push's quick actions;
            // the claimer can now close out a past ride from the detail screen.
            // Poster or claimer of a confirmed request (the complete_request RPC accepts both).
            // Drawn first: it is the filled primary action, and the outlined Unclaim follows it.
            let canMarkComplete = ride.status == .confirmed && ride.claimedBy != nil
                && (buttonState == .claimedByMe || buttonState == .isPoster)
            if canMarkComplete, RequestItem.ride(ride).eventTime < Date() {
                PrimaryButton(title: "ride_detail_mark_complete".localized) {
                    showCompleteSheet = true
                }
                .accessibilityIdentifier("ride.markComplete")
            }

            // Two states the shared button has no wording for get a plain note instead. A
            // co-requester is on the asking side of this ride, so "I Can Help!" on their own
            // shared ride made no sense. A ride nobody claimed before it was closed must not
            // read "Completed" here any more than on its status chip.
            let neutralNote: String? = {
                if buttonState == .canClaim && viewModel.isParticipant {
                    return "request_detail_participant_notice".localized
                }
                if buttonState == .completed && ride.isExpiredUnclaimed {
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
        RideDetailView(rideId: UUID())
    }
}

