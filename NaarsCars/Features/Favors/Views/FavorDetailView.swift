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
                    if let favor = viewModel.favor {
                        favorDetails(favor: favor)
                    } else if viewModel.isLoading {
                        LoadingView(message: "Loading favor details...")
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
                .onChange(of: navigationCoordinator.requestNavigationTarget) { _, target in
                    guard let target,
                          target.requestType == .favor,
                          target.requestId == favorId else { return }
                    handleRequestNavigation(target, proxy: proxy)
                }
            }
        }
        .navigationTitle("Favor Details")
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
        .alert("Delete Favor", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await viewModel.deleteFavor()
                        dismiss()
                    } catch {
                        // Error handling
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this favor request? This action cannot be undone.")
        }
        .sheet(isPresented: $showClaimSheet) {
            if let favor = viewModel.favor {
                ClaimSheet(
                    requestType: "favor",
                    requestTitle: favor.title,
                    onConfirm: {
                        Task {
                            do {
                                _ = try await claimViewModel.claim(requestType: "favor", requestId: favor.id)
                                if let conversationId = claimViewModel.conversationId {
                                    navigateToConversation = conversationId
                                }
                                await viewModel.loadFavor(id: favorId)
                            } catch {
                                // Error handled in viewModel
                            }
                        }
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
                        Task {
                            do {
                                try await claimViewModel.unclaim(requestType: "favor", requestId: favor.id)
                                await viewModel.loadFavor(id: favorId)
                            } catch {
                                // Error handled in viewModel
                            }
                        }
                    }
                )
                .id(RequestDetailAnchor.unclaimSheet.anchorId(for: .favor))
            }
        }
        .sheet(isPresented: $showCompleteSheet) {
            if let favor = viewModel.favor {
                CompleteSheet(
                    requestType: "favor",
                    requestTitle: favor.title,
                    onConfirm: {
                        Task {
                            do {
                                try await claimViewModel.complete(requestType: "favor", requestId: favor.id)
                                await viewModel.loadFavor(id: favorId)
                            } catch {
                                // Error handled in viewModel
                            }
                        }
                    }
                )
                .id(RequestDetailAnchor.completeSheet.anchorId(for: .favor))
                .onAppear { handleSectionAppeared(.completeSheet) }
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            if let favor = viewModel.favor, let claimerId = favor.claimedBy {
                let claimerName = favor.claimer?.name ?? "Someone"
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
        .trackScreen("FavorDetail")
    }
    
    @ViewBuilder
    private func favorDetails(favor: Favor) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Section: Status and Poster
            HStack(alignment: .center, spacing: 16) {
                if let poster = favor.poster {
                    UserAvatarLink(profile: poster, size: 60)
                }
                
                VStack(alignment: .leading, spacing: 4) {
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
                        Text("Requested by \(poster.name)")
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Details", systemImage: "info.circle.fill")
                        .font(.naarsTitle3)
                        .foregroundColor(.favorAccent)
                    Spacer()
                    Text("Hold location to copy")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.favorAccent)
                            .font(.title3)
                        AddressText(favor.location)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openInExternalMaps(favor: favor)
                    }
                    
                    Divider()
                    
                    HStack(spacing: 16) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(favor.date.dateString)
                                    .font(.naarsHeadline)
                                Text("Date")
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
                                    Text("Time")
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
                            Text("Estimated Duration")
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
            if let claimer = favor.claimer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Claimed by")
                        .font(.naarsTitle3)
                    
                    HStack(spacing: 12) {
                        UserAvatarLink(profile: claimer, size: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
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
                VStack(alignment: .leading, spacing: 16) {
                    if let requirements = favor.requirements, !requirements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Requirements", systemImage: "list.bullet.clipboard")
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
                requestId: favor.id,
                requestType: "favor",
                onPostQuestion: { question in
                    await viewModel.postQuestion(question)
                }
            )
            .id(RequestDetailAnchor.qaSection.anchorId(for: .favor))
            .requestHighlight(highlightedAnchor == .qaSection)
            .onAppear { handleSectionAppeared(.qaSection) }
            
            claimButtonSection(favor: favor)
                .id(RequestDetailAnchor.claimAction.anchorId(for: .favor))
                .requestHighlight(highlightedAnchor == .claimAction)
                .onAppear { handleSectionAppeared(.claimAction) }
            
            if favor.claimedBy != nil && favor.status != .open {
                messageAllParticipantsButton(favor: favor)
            }
            
            if viewModel.canEdit {
                addParticipantsButton(favor: favor)
            }
            
            if viewModel.canEdit {
                HStack(spacing: 16) {
                    if favor.status == .confirmed {
                        SecondaryButton(title: "Mark Complete") {
                            showCompleteSheet = true
                        }
                        .id(RequestDetailAnchor.completeAction.anchorId(for: .favor))
                        .requestHighlight(highlightedAnchor == .completeAction)
                        .onAppear { handleSectionAppeared(.completeAction) }
                    }
                    
                    SecondaryButton(title: "Edit") { showEditFavor = true }
                    SecondaryButton(title: "Delete") { showDeleteAlert = true }
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
        
        if target.anchor == .completeSheet {
            showCompleteSheet = true
        }
        
        navigationCoordinator.requestNavigationTarget = nil
        print("📍 [FavorDetailView] Deep link to \(target.anchor.rawValue)")
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
                print("ℹ️ [FavorDetailView] No unread \(anchor.rawValue) notifications to clear")
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
    private func messageAllParticipantsButton(favor: Favor) -> some View {
        Button {
            Task { await openOrCreateConversation(favor: favor) }
        } label: {
            HStack {
                Image(systemName: "message.fill")
                Text("Message All Participants")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.naarsPrimary)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func addParticipantsButton(favor: Favor) -> some View {
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
            print("🔴 Error adding participants to favor: \(error.localizedDescription)")
        }
    }
    
    private func openInExternalMaps(favor: Favor) {
        print("🗺️ [FavorDetailView] Opening external maps for favor: \(favor.id)")
        let location = favor.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Google Maps URL Scheme
        let googleMapsUrl = URL(string: "comgooglemaps://?q=\(location)&directionsmode=driving")
        let googleMapsWebUrl = URL(string: "https://www.google.com/maps/search/?api=1&query=\(location)")
        
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
                    print("🗺️ [FavorDetailView] Opened Apple Maps via MKMapItem")
                } catch {
                    print("🗺️ [FavorDetailView] Apple Maps failed: \(error.localizedDescription)")
                    // Fallback to simple URL
                    if let url = URL(string: "http://maps.apple.com/?q=\(location)") {
                        await UIApplication.shared.open(url)
                    }
                }
            }
        }
        
        if let url = googleMapsUrl, UIApplication.shared.canOpenURL(url) {
            print("🗺️ [FavorDetailView] Opening Google Maps App")
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else if let url = googleMapsWebUrl, UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        } else {
            print("🗺️ [FavorDetailView] Attempting Apple Maps")
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

