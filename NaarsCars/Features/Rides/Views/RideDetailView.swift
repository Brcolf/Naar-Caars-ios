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
    @State private var showCompleteSheet = false
    @State private var showReviewSheet = false
    @State private var showPhoneRequired = false
    @State private var navigateToProfile = false
    @State private var navigateToConversation: UUID?
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    @State private var highlightedAnchor: RequestDetailAnchor?
    @State private var highlightTask: Task<Void, Never>?
    @State private var clearedAnchors: Set<RequestDetailAnchor> = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let ride = viewModel.ride {
                        rideDetails(ride: ride)
                    } else if viewModel.isLoading {
                        LoadingView(message: "Loading ride details...")
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
                .onChange(of: navigationCoordinator.requestNavigationTarget) { _, target in
                    guard let target,
                          target.requestType == .ride,
                          target.requestId == rideId else { return }
                    handleRequestNavigation(target, proxy: proxy)
                }
            }
        }
        .navigationTitle("Ride Details")
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
        .alert("Delete Ride", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteRide()
                        dismiss()
                    } catch {
                        // Error handling
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this ride request? This action cannot be undone.")
        }
        .sheet(isPresented: $showClaimSheet) {
            if let ride = viewModel.ride {
                ClaimSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        Task {
                            do {
                                _ = try await claimViewModel.claim(requestType: "ride", requestId: ride.id)
                                if let conversationId = claimViewModel.conversationId {
                                    navigateToConversation = conversationId
                                }
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
        .sheet(isPresented: $showCompleteSheet) {
            if let ride = viewModel.ride {
                CompleteSheet(
                    requestType: "ride",
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    onConfirm: {
                        Task {
                            do {
                                try await claimViewModel.complete(requestType: "ride", requestId: ride.id)
                                await viewModel.loadRide(id: rideId)
                            } catch {
                                // Error handled in viewModel
                            }
                        }
                    }
                )
                .id(RequestDetailAnchor.completeSheet.anchorId(for: .ride))
                .onAppear { handleSectionAppeared(.completeSheet) }
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
        .trackScreen("RideDetail")
    }
    
    @ViewBuilder
    private func rideDetails(ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Section: Status and Poster
            HStack(alignment: .center, spacing: 16) {
                if let poster = ride.poster {
                    UserAvatarLink(profile: poster, size: 60)
                }
                
                VStack(alignment: .leading, spacing: 4) {
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
                        Text("Requested by \(poster.name)")
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.naarsTitle3)
                        .foregroundColor(.rideAccent)
                    Spacer()
                    Text("Hold address to copy")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PICKUP")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            AddressText(ride.pickup)
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 20)
                        .padding(.leading, 29)
                    
                    HStack(spacing: 16) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.rideAccent)
                            .font(.system(size: 20))
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DESTINATION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            AddressText(ride.destination)
                        }
                    }
                }
                
                if let estimatedCost = ride.estimatedCost {
                    Divider()
                    HStack {
                        Label("Estimated Rideshare Savings", systemImage: "dollarsign.circle.fill")
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
                    Label("Route Map", systemImage: "map.fill")
                        .font(.naarsTitle3)
                    Spacer()
                    Text("Tap to open in Maps")
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
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ride.date.dateString)
                                .font(.naarsHeadline)
                            Text("Date")
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
                            Text("Time")
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
                            Text("\(ride.seats) seat(s)")
                                .font(.naarsHeadline)
                            Text("Requested")
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
                    Text("Participants")
                        .font(.naarsTitle3)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
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
                    Text("Claimed by")
                        .font(.naarsTitle3)
                    
                    HStack(spacing: 12) {
                        UserAvatarLink(profile: claimer, size: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
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
                VStack(alignment: .leading, spacing: 16) {
                    if let notes = ride.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
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
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Gift/Compensation", systemImage: "gift.fill")
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
                    await viewModel.postQuestion(question)
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
                HStack(spacing: 16) {
                    if ride.status == .confirmed {
                        SecondaryButton(title: "Mark Complete") {
                            showCompleteSheet = true
                        }
                        .accessibilityIdentifier("ride.markComplete")
                        .id(RequestDetailAnchor.completeAction.anchorId(for: .ride))
                        .requestHighlight(highlightedAnchor == .completeAction)
                        .onAppear { handleSectionAppeared(.completeAction) }
                    }
                    
                    SecondaryButton(title: "Edit") { showEditRide = true }
                        .accessibilityIdentifier("ride.edit")
                    SecondaryButton(title: "Delete") { showDeleteAlert = true }
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
        
        if target.anchor == .completeSheet {
            showCompleteSheet = true
        }
        
        navigationCoordinator.requestNavigationTarget = nil
        print("📍 [RideDetailView] Deep link to \(target.anchor.rawValue)")
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
                print("ℹ️ [RideDetailView] No unread \(anchor.rawValue) notifications to clear")
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
                Text("Add Participants")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
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
            
            let conversation = try await MessageService.shared.createConversationWithUsers(
                userIds: Array(participantIds),
                createdBy: currentUserId,
                title: nil
            )
            navigateToConversation = conversation.id
        } catch {
            print("🔴 Error creating conversation: \(error.localizedDescription)")
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
            print("🔴 Error adding participants to ride: \(error.localizedDescription)")
        }
    }
    
    private func openInExternalMaps(ride: Ride) {
        print("🗺️ [RideDetailView] Opening external maps for ride: \(ride.id)")
        let pickup = ride.pickup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let destination = ride.destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Google Maps Universal Link (more reliable for multi-stop)
        // https://www.google.com/maps/dir/?api=1&origin=Current+Location&destination=[DEST]&waypoints=[PICKUP]&travelmode=driving
        let googleMapsUrl = URL(string: "comgooglemaps://?saddr=&daddr=\(destination)&waypoints=\(pickup)&directionsmode=driving")
        let googleMapsWebUrl = URL(string: "https://www.google.com/maps/dir/?api=1&origin=My+Location&destination=\(destination)&waypoints=\(pickup)&travelmode=driving")
        
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
                    print("🗺️ [RideDetailView] Opened Apple Maps via MKMapItem")
                } catch {
                    print("🗺️ [RideDetailView] Apple Maps multi-stop failed: \(error.localizedDescription)")
                    // Fallback to simple URL if geocoding fails
                    if let url = URL(string: "http://maps.apple.com/?saddr=\(pickup)&daddr=\(destination)") {
                        await UIApplication.shared.open(url)
                    }
                }
            }
        }
        
        if let url = googleMapsUrl, UIApplication.shared.canOpenURL(url) {
            print("🗺️ [RideDetailView] Opening Google Maps App")
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else if let url = googleMapsWebUrl, UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            // This is a backup check for the universal link
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else {
            print("🗺️ [RideDetailView] Attempting Apple Maps Multi-Stop")
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

