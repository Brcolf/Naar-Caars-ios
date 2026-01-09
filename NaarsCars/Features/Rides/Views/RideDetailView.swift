//
//  RideDetailView.swift
//  NaarsCars
//
//  View for displaying ride details
//

import SwiftUI

/// View for displaying ride details
struct RideDetailView: View {
    let rideId: UUID
    @StateObject private var viewModel = RideDetailViewModel()
    @StateObject private var claimViewModel = ClaimViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showEditRide = false
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
                if let ride = viewModel.ride {
                    // Poster info
                    if let poster = ride.poster {
                        UserAvatarLink(profile: poster, size: 60)
                    }
                    
                    // Status badge
                    HStack {
                        Text(ride.status.displayText)
                            .font(.naarsHeadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ride.status.color)
                            .cornerRadius(8)
                        
                        Spacer()
                    }
                    
                    // Route
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Route")
                            .font(.naarsTitle3)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.naarsPrimary)
                                .font(.title2)
                            Text(ride.pickup)
                                .font(.naarsBody)
                        }
                        
                        Image(systemName: "arrow.down")
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                        
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.naarsAccent)
                                .font(.title2)
                            Text(ride.destination)
                                .font(.naarsBody)
                        }
                    }
                    .cardStyle()
                    
                    // Date, time, seats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.naarsTitle3)
                        
                        HStack {
                            Label(ride.date.dateString, systemImage: "calendar")
                            Spacer()
                        }
                        
                        HStack {
                            Label(ride.time, systemImage: "clock")
                            Spacer()
                        }
                        
                        HStack {
                            Label("\(ride.seats) seat\(ride.seats == 1 ? "" : "s")", systemImage: "person.2")
                            Spacer()
                        }
                    }
                    .cardStyle()
                    
                    // Notes
                    if let notes = ride.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.naarsTitle3)
                            Text(notes)
                                .font(.naarsBody)
                        }
                        .cardStyle()
                    }
                    
                    // Gift
                    if let gift = ride.gift, !gift.isEmpty {
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
                        requestId: ride.id,
                        requestType: "ride",
                        onPostQuestion: { question in
                            await viewModel.postQuestion(question)
                        }
                    )
                    
                    // Claim/Unclaim/Complete button
                    claimButtonSection(ride: ride)
                    
                    // Message all participants button (only when claimed)
                    if ride.claimedBy != nil && ride.status != .open {
                        messageAllParticipantsButton(ride: ride)
                    }
                    
                    // Add participants button (for poster)
                    if viewModel.isPoster {
                        addParticipantsButton(ride: ride)
                    }
                    
                    // Action buttons for poster
                    if viewModel.isPoster {
                        HStack(spacing: 16) {
                            if ride.status == .confirmed {
                                SecondaryButton(title: "Mark Complete") {
                                    showCompleteSheet = true
                                }
                            }
                            
                            SecondaryButton(title: "Edit") {
                                showEditRide = true
                            }
                            
                            SecondaryButton(title: "Delete") {
                                showDeleteAlert = true
                            }
                        }
                    }
                } else if viewModel.isLoading {
                    LoadingView(message: "Loading ride details...")
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error,
                        retryAction: {
                            Task {
                                await viewModel.loadRide(id: rideId)
                            }
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Ride Details")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadRide(id: rideId)
        }
        .task {
            await viewModel.loadRide(id: rideId)
        }
        .sheet(isPresented: $showEditRide) {
            if let ride = viewModel.ride {
                EditRideView(ride: ride)
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
                            Task {
                                await addParticipantsToRide(Array(selectedUserIds))
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
    private func messageAllParticipantsButton(ride: Ride) -> some View {
        Button {
            Task {
                await openOrCreateConversation(ride: ride)
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
        var ids: [UUID] = [ride.userId] // Poster
        if let claimedBy = ride.claimedBy {
            ids.append(claimedBy)
        }
        // TODO: Add ride_participants when that data is available
        return ids
    }
    
    private func openOrCreateConversation(ride: Ride) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            // Get or create conversation for this ride
            let conversation = try await MessageService.shared.createOrGetRequestConversation(
                rideId: ride.id,
                favorId: nil,
                createdBy: currentUserId
            )
            
            // Collect all participant IDs (poster, claimer, current user)
            var participantIds: Set<UUID> = [ride.userId] // Poster
            if let claimedBy = ride.claimedBy {
                participantIds.insert(claimedBy)
            }
            participantIds.insert(currentUserId) // Ensure current user is included
            // TODO: Add ride_participants when that data is available
            
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
                print("ℹ️ [RideDetailView] Current user may already be a participant: \(error.localizedDescription)")
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
    
    private func addParticipantsToRide(_ userIds: [UUID]) async {
        guard let currentUserId = AuthService.shared.currentUserId,
              let ride = viewModel.ride else { return }
        
        do {
            try await RideService.shared.addRideParticipants(
                rideId: ride.id,
                userIds: userIds,
                addedBy: currentUserId
            )
            // Reload ride to show new participants
            await viewModel.loadRide(id: rideId)
        } catch {
            print("🔴 Error adding participants to ride: \(error.localizedDescription)")
        }
    }
    
    @ViewBuilder
    private func claimButtonSection(ride: Ride) -> some View {
        let authService = AuthService.shared
        let currentUserId = authService.currentUserId
        
        // Determine button state
        let buttonState: ClaimButtonState = {
            if viewModel.isPoster {
                return .isPoster
            } else if ride.status == .completed {
                return .completed
            } else if let claimedBy = ride.claimedBy {
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
        RideDetailView(rideId: UUID())
    }
}

