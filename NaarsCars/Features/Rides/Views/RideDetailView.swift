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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let ride = viewModel.ride {
                    // Poster info
                    if let poster = ride.poster {
                        UserAvatarLink(profile: poster, size: 60)
                    }
                    
                    // Participants (if any)
                    if let participants = ride.participants, !participants.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Participants")
                                .font(.naarsTitle3)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(participants) { participant in
                                        VStack(spacing: 4) {
                                            UserAvatarLink(profile: participant, size: 50)
                                            Text(participant.name)
                                                .font(.naarsCaption)
                                                .lineLimit(1)
                                                .frame(width: 60)
                                        }
                                    }
                                }
                            }
                        }
                        .cardStyle()
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
                    
                    // Estimated cost (if available)
                    if let estimatedCost = ride.estimatedCost {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Estimated Rideshare Cost")
                                .font(.naarsTitle3)
                            
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .foregroundColor(.naarsPrimary)
                                Text(RideCostEstimator.formatCost(estimatedCost))
                                    .font(.naarsHeadline)
                            }
                        }
                        .cardStyle()
                    }
                    
                    // Map view showing route
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route Map")
                            .font(.naarsTitle3)
                        
                        RouteMapView(pickup: ride.pickup, destination: ride.destination)
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
                    
                    // Add participants button (for poster/participants)
                    if viewModel.canEdit {
                        addParticipantsButton(ride: ride)
                    }
                    
                    // Action buttons for poster/participants
                    if viewModel.canEdit {
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
        .sheet(isPresented: $showReviewSheet) {
            if let ride = viewModel.ride, let claimerId = ride.claimedBy {
                // Get claimer profile name
                let claimerName = ride.claimer?.name ?? "Someone"
                LeaveReviewView(
                    requestType: "ride",
                    requestId: ride.id,
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    fulfillerId: claimerId,
                    fulfillerName: claimerName,
                    onReviewSubmitted: {
                        Task {
                            await viewModel.loadRide(id: rideId)
                        }
                    },
                    onReviewSkipped: {
                        Task {
                            await viewModel.loadRide(id: rideId)
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
        .trackScreen("RideDetail")
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
        // Add participants
        if let participants = ride.participants {
            ids.append(contentsOf: participants.map { $0.id })
        }
        return ids
    }
    
    private func openOrCreateConversation(ride: Ride) async {
        guard let currentUserId = AuthService.shared.currentUserId else { return }
        
        do {
            // Collect all relevant user IDs (poster, claimer, participants, current user)
            var participantIds: Set<UUID> = [ride.userId] // Poster
            if let claimedBy = ride.claimedBy {
                participantIds.insert(claimedBy)
            }
            // Add participants
            if let participants = ride.participants {
                participantIds.formUnion(participants.map { $0.id })
            }
            participantIds.insert(currentUserId) // Ensure current user is included
            
            // Create conversation with all relevant users
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

