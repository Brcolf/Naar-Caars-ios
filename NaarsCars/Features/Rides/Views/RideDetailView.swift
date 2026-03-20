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
    @State private var showGuestPrompt = false
    @State private var guestRestrictionReason: GuestRestrictionReason = .claimRide
    @State private var showEditRide = false
    @State private var showDeleteAlert = false
    @State private var showClaimSheet = false
    @State private var showUnclaimSheet = false
    @State private var showReviewSheet = false
    @State private var showPhoneRequired = false
    @State private var showProfileFromPhoneRequired = false
    @State private var selectedConversationId: UUID?
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var highlightedAnchor: RequestDetailAnchor?
    @State private var highlightTask: Task<Void, Never>?
    @State private var clearedAnchors: Set<RequestDetailAnchor> = []
    @State private var toastMessage: String? = nil
    @State private var showSuccess = false
    @State private var isOpeningMaps = false
    @State private var openMapsTask: Task<Void, Never>?
    @State private var openMapsLocationProvider: CurrentLocationProvider?
    @AppStorage("preferredMapsApp") private var preferredMapsApp: String = ""
    @State private var showMapsChoiceDialog = false
    @State private var showReportSheet = false
    @State private var hasReported = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                    if let ride = viewModel.ride {
                        rideDetails(ride: ride)
                    } else if viewModel.isLoading {
                        LoadingView(message: "ride_detail_loading".localized)
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
        .navigationTitle("ride_detail_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.isPoster, viewModel.ride != nil, !appState.isGuest {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if hasReported {
                        Image(systemName: "flag.fill")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary.opacity(0.5))
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
        .sheet(isPresented: $showGuestPrompt) {
            GuestSignInPromptView(
                reason: guestRestrictionReason,
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
        .refreshable { await viewModel.loadRide(id: rideId) }
        .task {
            await viewModel.loadRide(id: rideId)
            viewModel.checkCalendarOffer()
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
                        toastMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("ride_detail_delete_confirmation".localized)
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
        .sheet(isPresented: $showClaimSheet) {
            if let ride = viewModel.ride {
                ClaimSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        try await claimViewModel.claim(requestType: "ride", requestId: ride.id)
                        await viewModel.loadRide(id: rideId)
                    }
                )
                .id(RequestDetailAnchor.claimSheet.anchorId(for: .ride))
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
                let claimerName = ride.claimer?.name ?? "Someone"
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
        .sheet(isPresented: $showPhoneRequired) {
            PhoneRequiredSheet(showProfileScreen: $showProfileFromPhoneRequired)
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
        .navigationDestination(isPresented: $showProfileFromPhoneRequired) {
            MyProfileView()
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
                        if !selectedUserIds.isEmpty {
                            Task { await addParticipantsToRide(Array(selectedUserIds)) }
                        }
                        showAddParticipants = false
                        selectedUserIds = []
                    }
                )
            }
        }
        .toast(message: $toastMessage)
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
        VStack(alignment: .leading, spacing: 20) {
            // Header Section: Status and Poster
            HStack(alignment: .center, spacing: Constants.Spacing.md) {
                if let poster = ride.poster {
                    UserAvatarLink(profile: poster, size: 60)
                }
                
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(ride.status.displayText)
                        .font(.naarsHeadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ride.status.color)
                        .cornerRadius(8)
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
                HStack {
                    Label("ride_detail_route".localized, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.naarsTitle3)
                        .foregroundColor(.rideAccent)
                    Spacer()
                    Text("ride_detail_hold_to_copy".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Constants.Spacing.md) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.green)
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
                
                if let estimatedCost = ride.estimatedCost {
                    Divider()
                    HStack {
                        Label("ride_detail_estimated_savings".localized, systemImage: "dollarsign.circle.fill")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(RideCostEstimator.formatCost(estimatedCost))
                            .font(.naarsHeadline)
                            .foregroundColor(.naarsPrimary)
                    }
                }
            }
            .cardStyle()
            
            // Map Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("ride_detail_route_map".localized, systemImage: "map.fill")
                        .font(.naarsTitle3)
                    Spacer()
                    if isOpeningMaps {
                        Text("ride_detail_opening_maps".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("ride_detail_tap_open_maps".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }

                if appState.isGuest {
                    VStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("guest_map_hidden".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RouteMapView(pickup: ride.pickup, destination: ride.destination)
                        .contentShape(Rectangle()) // Ensure the entire area is tappable
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
            
            // Time and Seats Info
            HStack(spacing: Constants.Spacing.md) {
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
                            HStack(spacing: 4) {
                                Text(ride.time)
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
                            Text("ride_detail_seats_count".localized(with: ride.seats))
                                .font(.naarsHeadline)
                            Text("ride_detail_requested".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.naarsPrimary)
                    }
                    
                    // Placeholder for potential future field or empty space to align
                    Spacer().frame(height: 34)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle()
            
            // Participants Section
            if let participants = ride.participants, !participants.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ride_detail_participants".localized)
                        .font(.naarsTitle3)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Constants.Spacing.md) {
                            ForEach(participants) { participant in
                                VStack(spacing: 6) {
                                    UserAvatarLink(profile: participant, size: 50)
                                    Text(participant.name)
                                        .font(.naarsCaption)
                                        .lineLimit(1)
                                        .frame(width: 60)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .cardStyle()
            }
            
            // Claimer Section
            if let claimer = ride.claimer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ride_detail_claimed_by".localized)
                        .font(.naarsTitle3)
                    
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

            // Review Section (for completed rides)
            if ride.claimedBy != nil {
                RequestReviewSection(
                    requestType: "ride",
                    requestId: ride.id,
                    posterId: ride.userId,
                    claimerId: ride.claimedBy,
                    isCompleted: ride.status == .completed,
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onReviewSubmitted: {
                        Task { await viewModel.loadRide(id: rideId) }
                    }
                )
            }

            // Flight (persisted or parsed from notes; tappable to open status search)
            if let flightInfo = FlightInfo.displayInfo(for: ride) {
                FlightRowView(flightInfo: flightInfo, style: .detail)
                    .cardStyle()
            }
            
            // Notes & Gift
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
                .cardStyle()
            }
            
            RequestQAView(
                qaItems: viewModel.qaItems,
                requestId: ride.id,
                requestType: "ride",
                onPostQuestion: { question in
                    if appState.isGuest {
                        guestRestrictionReason = .askQuestion
                        showGuestPrompt = true
                        return
                    }
                    let countBefore = viewModel.qaItems.count
                    await viewModel.postQuestion(question)
                    if viewModel.qaItems.count > countBefore {
                        toastMessage = "toast_question_posted".localized
                    }
                },
                isClaimed: ride.claimedBy != nil,
                onMessageParticipants: ride.claimedBy == nil ? nil : {
                    if appState.isGuest {
                        guestRestrictionReason = .sendMessage
                        showGuestPrompt = true
                        return
                    }
                    Task { await openOrCreateConversation(ride: ride) }
                }
            )
            .id(RequestDetailAnchor.qaSection.anchorId(for: .ride))
            .requestHighlight(highlightedAnchor == .qaSection)
            .onAppear { handleSectionAppeared(.qaSection) }
            
            claimButtonSection(ride: ride)
                .id(RequestDetailAnchor.claimAction.anchorId(for: .ride))
                .requestHighlight(highlightedAnchor == .claimAction)
                .onAppear { handleSectionAppeared(.claimAction) }
            
            if viewModel.canEdit {
                addParticipantsButton(ride: ride)
                    .accessibilityIdentifier("ride.addParticipants")
            }
            
            if viewModel.canEdit {
                HStack(spacing: Constants.Spacing.md) {
                    SecondaryButton(title: "ride_detail_edit".localized) { showEditRide = true }
                        .accessibilityIdentifier("ride.edit")
                    SecondaryButton(title: "ride_detail_delete".localized) { showDeleteAlert = true }
                        .accessibilityIdentifier("ride.delete")
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
                await BadgeCountManager.shared.refreshAllBadges(reason: "requestSectionViewed")
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
            .cornerRadius(12)
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
    
    private func openOrCreateConversation(ride: Ride) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            var participantIds: Set<UUID> = [ride.userId]
            if let claimedBy = ride.claimedBy { participantIds.insert(claimedBy) }
            if let participants = ride.participants {
                participantIds.formUnion(participants.map { $0.id })
            }
            participantIds.insert(currentUserId)
            
            let conversation = try await ConversationService.shared.createConversationWithUsers(
                userIds: Array(participantIds),
                createdBy: currentUserId,
                title: nil
            )
            selectedConversationId = conversation.id
        } catch {
            AppLogger.error("rides", "Error creating conversation: \(error.localizedDescription)")
        }
    }
    
    private func addParticipantsToRide(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId,
              let ride = viewModel.ride else { return }
        
        do {
            try await RideService.shared.addRideParticipants(
                rideId: ride.id,
                userIds: userIds,
                addedBy: currentUserId
            )
            await viewModel.loadRide(id: rideId)
        } catch {
            AppLogger.error("rides", "Error adding participants to ride: \(error.localizedDescription)")
        }
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
    private func claimButtonSection(ride: Ride) -> some View {
        if appState.isGuest {
            PrimaryButton(title: "guest_prompt_title_claim_ride".localized) {
                guestRestrictionReason = .claimRide
                showGuestPrompt = true
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

#Preview {
    NavigationStack {
        RideDetailView(rideId: UUID())
    }
}

