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
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showEditRide = false
    @State private var showDeleteAlert = false
    @State private var showClaimSheet = false
    @State private var showUnclaimSheet = false
    @State private var showReviewSheet = false
    @State private var showPhoneRequired = false
    @State private var navigateToProfile = false
    @State private var navigateToConversation: UUID?
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var highlightedAnchor: RequestDetailAnchor?
    @State private var highlightTask: Task<Void, Never>?
    @State private var clearedAnchors: Set<RequestDetailAnchor> = []
    @State private var toastMessage: String? = nil
    @State private var showSuccess = false
    
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
                .onChange(of: navigationCoordinator.requestNavigationTarget) { _, _ in
                    handlePendingRequestNavigation(proxy: proxy)
                }
                .onAppear {
                    handlePendingRequestNavigation(proxy: proxy)
                }
            }
        }
        .navigationTitle("ride_detail_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.loadRide(id: rideId) }
        .task { await viewModel.loadRide(id: rideId) }
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
                        // Error handling
                    }
                }
            }
        } message: {
            Text("ride_detail_delete_confirmation".localized)
        }
        .sheet(isPresented: $showClaimSheet) {
            if let ride = viewModel.ride {
                ClaimSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        Task {
                            do {
                                try await claimViewModel.claim(requestType: "ride", requestId: ride.id)
                                await viewModel.loadRide(id: rideId)
                            } catch {
                                // Error handled in viewModel
                            }
                        }
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
                        Task {
                            do {
                                try await claimViewModel.unclaim(requestType: "ride", requestId: ride.id)
                                await viewModel.loadRide(id: rideId)
                            } catch {
                                // Error handled in viewModel
                            }
                        }
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
            PhoneRequiredSheet(navigateToProfile: $navigateToProfile)
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
        .navigationDestination(isPresented: $navigateToProfile) {
            MyProfileView()
        }
        .navigationDestination(item: $navigateToConversation) { conversationId in
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
                            AddressText(ride.pickup)
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
                            AddressText(ride.destination)
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
                    Text("ride_detail_tap_open_maps".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                RouteMapView(pickup: ride.pickup, destination: ride.destination)
                    .contentShape(Rectangle()) // Ensure the entire area is tappable
                    .onTapGesture {
                        openInExternalMaps(ride: ride)
                    }
            }
            .cardStyle()
            
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
                            Text(ride.time)
                                .font(.naarsHeadline)
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
            
            // Notes & Gift
            if (ride.notes != nil && !ride.notes!.isEmpty) || (ride.gift != nil && !ride.gift!.isEmpty) {
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
                    
                    if ride.notes != nil && !ride.notes!.isEmpty && ride.gift != nil && !ride.gift!.isEmpty {
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
                    let countBefore = viewModel.qaItems.count
                    await viewModel.postQuestion(question)
                    if viewModel.qaItems.count > countBefore {
                        toastMessage = "toast_question_posted".localized
                    }
                },
                isClaimed: ride.claimedBy != nil,
                onMessageParticipants: ride.claimedBy == nil ? nil : {
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
        
        navigationCoordinator.requestNavigationTarget = nil
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
            navigateToConversation = conversation.id
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
    
    private func openInExternalMaps(ride: Ride) {
        AppLogger.info("rides", "[RideDetailView] Opening external maps for ride: \(ride.id)")
        let pickup = ride.pickup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let destination = ride.destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Google Maps Universal Link (more reliable for multi-stop)
        // https://www.google.com/maps/dir/?api=1&origin=Current+Location&destination=[DEST]&waypoints=[PICKUP]&travelmode=driving
        let googleMapsUrl = URL(string: "comgooglemaps://?saddr=&daddr=\(destination)&waypoints=\(pickup)&directionsmode=driving")
        let googleMapsWebUrl = URL(string: "\(Constants.URLs.googleMapsDirections)?api=1&origin=My+Location&destination=\(destination)&waypoints=\(pickup)&travelmode=driving")
        
        // Apple Maps multi-stop via MKMapItem
        // This is the most robust way to handle multiple stops in Apple Maps on iOS
        let appleMapsMultiStop = {
            let geocoder = CLGeocoder()
            Task {
                do {
                    let pickupPlacemarks = try await geocoder.geocodeAddressString(ride.pickup)
                    let destPlacemarks = try await geocoder.geocodeAddressString(ride.destination)
                    
                    guard let pickupPlacemark = pickupPlacemarks.first,
                          let destPlacemark = destPlacemarks.first else {
                        throw NSError(domain: "Maps", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not geocode addresses"])
                    }
                    
                    let pickupItem = MKMapItem(placemark: MKPlacemark(placemark: pickupPlacemark))
                    pickupItem.name = "Pickup: \(ride.pickup)"
                    
                    let destItem = MKMapItem(placemark: MKPlacemark(placemark: destPlacemark))
                    destItem.name = "Destination: \(ride.destination)"
                    
                    // Launch Apple Maps with current location as start, then pickup, then destination
                    // Note: MKMapItem.openMaps only supports a destination, but we can pass multiple items
                    // The first item in the array is the destination, but if we want current -> pickup -> dest, 
                    // we use the direction mode to help.
                    let launchOptions = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
                    MKMapItem.openMaps(with: [pickupItem, destItem], launchOptions: launchOptions)
                    AppLogger.info("rides", "[RideDetailView] Opened Apple Maps via MKMapItem")
                } catch {
                    AppLogger.warning("rides", "[RideDetailView] Apple Maps multi-stop failed: \(error.localizedDescription)")
                    // Fallback to simple URL if geocoding fails
                    if let url = URL(string: "http://maps.apple.com/?saddr=\(pickup)&daddr=\(destination)") {
                        await UIApplication.shared.open(url)
                    }
                }
            }
        }
        
        if let url = googleMapsUrl, UIApplication.shared.canOpenURL(url) {
            AppLogger.info("rides", "[RideDetailView] Opening Google Maps App")
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else if let url = googleMapsWebUrl, UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            // This is a backup check for the universal link
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else {
            AppLogger.info("rides", "[RideDetailView] Attempting Apple Maps Multi-Stop")
            appleMapsMultiStop()
        }
    }
    
    @ViewBuilder
    private func claimButtonSection(ride: Ride) -> some View {
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

#Preview {
    NavigationStack {
        RideDetailView(rideId: UUID())
    }
}

