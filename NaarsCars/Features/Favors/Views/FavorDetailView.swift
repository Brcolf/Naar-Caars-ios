//
//  FavorDetailView.swift
//  NaarsCars
//
//  View for displaying favor details
//

import SwiftUI

/// View for displaying favor details
struct FavorDetailView: View {
    let favorId: UUID
    @StateObject private var viewModel = FavorDetailViewModel()
    @StateObject private var claimViewModel = ClaimViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEditFavor = false
    @State private var showDeleteAlert = false
    @State private var showClaimSheet = false
    @State private var showUnclaimSheet = false
    @State private var showCompleteSheet = false
    @State private var showPhoneRequired = false
    @State private var navigateToProfile = false
    @State private var navigateToConversation: UUID?
    @State private var showAddParticipants = false
    @State private var selectedUserIds: Set<UUID> = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let favor = viewModel.favor {
                    // Poster info
                    if let poster = favor.poster {
                        UserAvatarLink(profile: poster, size: 60)
                    }
                    
                    // Status badge
                    HStack {
                        Text(favor.status.displayText)
                            .font(.naarsHeadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(favor.status.color)
                            .cornerRadius(8)
                        
                        Spacer()
                    }
                    
                    // Title
                    Text(favor.title)
                        .font(.naarsTitle2)
                    
                    // Description
                    if let description = favor.description, !description.isEmpty {
                        Text(description)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }
                    
                    // Location and Duration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.naarsTitle3)
                        
                        HStack {
                            Label(favor.location, systemImage: "mappin.circle.fill")
                            Spacer()
                        }
                        
                        HStack {
                            Label(favor.duration.displayText, systemImage: favor.duration.icon)
                            Spacer()
                        }
                        
                        HStack {
                            Label(favor.date.dateString, systemImage: "calendar")
                            Spacer()
                        }
                        
                        if let time = favor.time {
                            HStack {
                                Label(time, systemImage: "clock")
                                Spacer()
                            }
                        }
                    }
                    .cardStyle()
                    
                    // Requirements
                    if let requirements = favor.requirements, !requirements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requirements")
                                .font(.naarsTitle3)
                            Text(requirements)
                                .font(.naarsBody)
                        }
                        .cardStyle()
                    }
                    
                    // Gift
                    if let gift = favor.gift, !gift.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gift/Compensation")
                                .font(.naarsTitle3)
                            Text(gift)
                                .font(.naarsBody)
                        }
                        .cardStyle()
                    }
                    
                    // Q&A Section
                    RequestQAView(
                        qaItems: viewModel.qaItems,
                        requestId: favor.id,
                        requestType: "favor",
                        onPostQuestion: { question in
                            await viewModel.postQuestion(question)
                        }
                    )
                    
                    // Claim/Unclaim/Complete button
                    claimButtonSection(favor: favor)
                    
                    // Message all participants button (only when claimed)
                    if favor.claimedBy != nil && favor.status != .open {
                        messageAllParticipantsButton(favor: favor)
                    }
                    
                    // Add participants button (for poster)
                    if viewModel.isPoster {
                        addParticipantsButton(favor: favor)
                    }
                    
                    // Action buttons for poster
                    if viewModel.isPoster {
                        HStack(spacing: 16) {
                            if favor.status == .confirmed {
                                SecondaryButton(title: "Mark Complete") {
                                    showCompleteSheet = true
                                }
                            }
                            
                            SecondaryButton(title: "Edit") {
                                showEditFavor = true
                            }
                            
                            SecondaryButton(title: "Delete") {
                                showDeleteAlert = true
                            }
                        }
                    }
                } else if viewModel.isLoading {
                    LoadingView(message: "Loading favor details...")
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error,
                        retryAction: {
                            Task {
                                await viewModel.loadFavor(id: favorId)
                            }
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Favor Details")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadFavor(id: favorId)
        }
        .task {
            await viewModel.loadFavor(id: favorId)
        }
        .sheet(isPresented: $showEditFavor) {
            if let favor = viewModel.favor {
                EditFavorView(favor: favor)
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
                            Task {
                                await addParticipantsToFavor(Array(selectedUserIds))
                            }
                        }
                        showAddParticipants = false
                        selectedUserIds = []
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    @ViewBuilder
    private func messageAllParticipantsButton(favor: Favor) -> some View {
        Button {
            Task {
                await openOrCreateConversation(favor: favor)
            }
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
        var ids: [UUID] = [favor.userId] // Poster
        if let claimedBy = favor.claimedBy {
            ids.append(claimedBy)
        }
        // TODO: Add favor_participants when that data is available
        return ids
    }
    
    private func openOrCreateConversation(favor: Favor) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            // Get or create conversation for this favor
            let conversation = try await MessageService.shared.createOrGetRequestConversation(
                rideId: nil,
                favorId: favor.id,
                createdBy: currentUserId
            )
            
            // Collect all participant IDs (poster, claimer, current user)
            var participantIds: Set<UUID> = [favor.userId] // Poster
            if let claimedBy = favor.claimedBy {
                participantIds.insert(claimedBy)
            }
            participantIds.insert(currentUserId) // Ensure current user is included
            // TODO: Add favor_participants when that data is available
            
            // Add participants (will skip if already added)
            // First ensure current user is a participant so they can add others
            do {
                try await MessageService.shared.addParticipantsToConversation(
                    conversationId: conversation.id,
                    userIds: [currentUserId],
                    addedBy: currentUserId,
                    createAnnouncement: false
                )
            } catch {
                // If current user is already a participant, that's fine
                print("ℹ️ [FavorDetailView] Current user may already be a participant: \(error.localizedDescription)")
            }
            
            // Now add all other participants
            let otherParticipants = Array(participantIds.filter { $0 != currentUserId })
            if !otherParticipants.isEmpty {
                try await MessageService.shared.addParticipantsToConversation(
                    conversationId: conversation.id,
                    userIds: otherParticipants,
                    addedBy: currentUserId,
                    createAnnouncement: false
                )
            }
            
            navigateToConversation = conversation.id
        } catch {
            print("🔴 Error opening conversation: \(error.localizedDescription)")
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
            // Reload favor to show new participants
            await viewModel.loadFavor(id: favorId)
        } catch {
            print("🔴 Error adding participants to favor: \(error.localizedDescription)")
        }
    }
    
    @ViewBuilder
    private func claimButtonSection(favor: Favor) -> some View {
        let authService = AuthService.shared
        let currentUserId = authService.currentUserId
        
        // Determine button state
        let buttonState: ClaimButtonState = {
            if viewModel.isPoster {
                return .isPoster
            } else if favor.status == .completed {
                return .completed
            } else if let claimedBy = favor.claimedBy {
                if claimedBy == currentUserId {
                    return .claimedByMe
                } else {
                    return .claimedByOther
                }
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

