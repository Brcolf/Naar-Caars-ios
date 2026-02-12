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
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showEditFavor = false
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
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                    if let favor = viewModel.favor {
                        favorDetails(favor: favor)
                    } else if viewModel.isLoading {
                        LoadingView(message: "favor_detail_loading".localized)
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
        .navigationTitle("favor_detail_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.loadFavor(id: favorId) }
        .task { await viewModel.loadFavor(id: favorId) }
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
                        // Error handling
                    }
                }
            }
        } message: {
            Text("favor_detail_delete_confirmation".localized)
        }
        .sheet(isPresented: $showClaimSheet) {
            if let favor = viewModel.favor {
                ClaimSheet(
                    requestType: "favor",
                    requestTitle: favor.title,
                    onConfirm: {
                        try await claimViewModel.claim(requestType: "favor", requestId: favor.id)
                        await viewModel.loadFavor(id: favorId)
                    }
                )
                .id(RequestDetailAnchor.claimSheet.anchorId(for: .favor))
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
            if let favor = viewModel.favor {
                UserSearchView(
                    selectedUserIds: $selectedUserIds,
                    excludeUserIds: getExistingParticipantIds(favor: favor),
                    onDismiss: {
                        if !selectedUserIds.isEmpty {
                            Task { await addParticipantsToFavor(Array(selectedUserIds)) }
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
        .trackScreen("FavorDetail")
    }
    
    @ViewBuilder
    private func favorDetails(favor: Favor) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Section: Status and Poster
            HStack(alignment: .center, spacing: Constants.Spacing.md) {
                if let poster = favor.poster {
                    UserAvatarLink(profile: poster, size: 60)
                }
                
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(favor.status.displayText)
                        .font(.naarsHeadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(favor.status.color)
                        .cornerRadius(8)
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
            
            // Title & Description Card
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
            
            // Location & Time Card
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                HStack {
                    Label("favor_detail_details".localized, systemImage: "info.circle.fill")
                        .font(.naarsTitle3)
                        .foregroundColor(.favorAccent)
                    Spacer()
                    Text("favor_detail_hold_to_copy".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.favorAccent)
                            .font(.naarsTitle3)
                        AddressText(favor.location)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openInExternalMaps(favor: favor)
                    }
                    
                    Divider()
                    
                    HStack(spacing: Constants.Spacing.md) {
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
                                    Text(time)
                                        .font(.naarsHeadline)
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
            
            // Participants Section
            if let participants = favor.participants, !participants.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("favor_detail_participants".localized)
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
            if let claimer = favor.claimer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("favor_detail_claimed_by".localized)
                        .font(.naarsTitle3)
                    
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
            
            // Requirements & Gift
            if (favor.requirements != nil && !favor.requirements!.isEmpty) || (favor.gift != nil && !favor.gift!.isEmpty) {
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
                    
                    if favor.requirements != nil && !favor.requirements!.isEmpty && favor.gift != nil && !favor.gift!.isEmpty {
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
                .cardStyle()
            }
            
            RequestQAView(
                qaItems: viewModel.qaItems,
                requestId: favor.id,
                requestType: "favor",
                onPostQuestion: { question in
                    let countBefore = viewModel.qaItems.count
                    await viewModel.postQuestion(question)
                    if viewModel.qaItems.count > countBefore {
                        toastMessage = "toast_question_posted".localized
                    }
                },
                isClaimed: favor.claimedBy != nil,
                onMessageParticipants: favor.claimedBy == nil ? nil : {
                    Task { await openOrCreateConversation(favor: favor) }
                }
            )
            .id(RequestDetailAnchor.qaSection.anchorId(for: .favor))
            .requestHighlight(highlightedAnchor == .qaSection)
            .onAppear { handleSectionAppeared(.qaSection) }
            
            claimButtonSection(favor: favor)
                .id(RequestDetailAnchor.claimAction.anchorId(for: .favor))
                .requestHighlight(highlightedAnchor == .claimAction)
                .onAppear { handleSectionAppeared(.claimAction) }
            
            if viewModel.canEdit {
                addParticipantsButton(favor: favor)
                    .accessibilityIdentifier("favor.addParticipants")
            }
            
            if viewModel.canEdit {
                HStack(spacing: Constants.Spacing.md) {
                    SecondaryButton(title: "favor_detail_edit".localized) { showEditFavor = true }
                        .accessibilityIdentifier("favor.edit")
                    SecondaryButton(title: "favor_detail_delete".localized) { showDeleteAlert = true }
                        .accessibilityIdentifier("favor.delete")
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
                await BadgeCountManager.shared.refreshAllBadges(reason: "requestSectionViewed")
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
            .cornerRadius(12)
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
    
    private func openOrCreateConversation(favor: Favor) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            var participantIds: Set<UUID> = [favor.userId]
            if let claimedBy = favor.claimedBy { participantIds.insert(claimedBy) }
            if let participants = favor.participants {
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
            AppLogger.error("favors", "Error creating conversation: \(error.localizedDescription)")
        }
    }
    
    private func addParticipantsToFavor(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId,
              let favor = viewModel.favor else { return }
        
        do {
            try await FavorService.shared.addFavorParticipants(
                favorId: favor.id,
                userIds: userIds,
                addedBy: currentUserId
            )
            await viewModel.loadFavor(id: favorId)
        } catch {
            AppLogger.error("favors", "Error adding participants to favor: \(error.localizedDescription)")
        }
    }
    
    private func openInExternalMaps(favor: Favor) {
        AppLogger.info("favors", "Opening external maps for favor: \(favor.id)")
        let location = favor.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
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
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(location)") {
                        await UIApplication.shared.open(url)
                    }
                }
            }
        }
        
        if let url = googleMapsUrl, UIApplication.shared.canOpenURL(url) {
            AppLogger.info("favors", "Opening Google Maps App")
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else if let url = googleMapsWebUrl, UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else {
            AppLogger.info("favors", "Attempting Apple Maps")
            appleMapsOpen()
        }
    }
    
    @ViewBuilder
    private func claimButtonSection(favor: Favor) -> some View {
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
        FavorDetailView(favorId: UUID())
    }
}

