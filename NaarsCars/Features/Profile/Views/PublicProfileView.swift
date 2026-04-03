//
//  PublicProfileView.swift
//  NaarsCars
//
//  View for displaying other users' profiles with phone masking
//

import SwiftUI

/// View for displaying public user profiles
struct PublicProfileView: View {
    let userId: UUID
    @StateObject private var viewModel = PublicProfileViewModel()
    @Environment(AppState.self) var appState
    @State private var isPhoneRevealed = false
    @State private var badges: [LeaderboardBadge] = []
    @State private var showBlockConfirmation = false
    @State private var isBlocking = false
    @State private var blockError: String?
    @State private var didBlock = false
    @State private var showGuestPrompt = false
    @State private var guestRestrictionReason: GuestRestrictionReason = .sendMessage
    @State private var showReportSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let profile = viewModel.profile {
                    // Header Section
                    headerSection(profile: profile)
                    
                    // Stats Section
                    statsSection(
                        rating: viewModel.averageRating,
                        fulfilledCount: viewModel.fulfilledCount
                    )
                    
                    // Phone Section (if available — hidden for guests)
                    if !appState.isGuest, let phoneNumber = profile.phoneNumber {
                        phoneSection(phoneNumber: phoneNumber, profile: profile)
                    }
                    
                    // Send Message Button (if not own profile)
                    if profile.id != appState.currentUser?.id {
                        sendMessageButton(userId: profile.id)
                    }
                    
                    // Badges Section
                    BadgeListSection(earnedBadges: badges)
                        .padding(.horizontal)

                    // Reviews Section
                    reviewsSection()
                } else if viewModel.isLoading {
                    LoadingView(message: "profile_loading".localized)
                } else {
                    ErrorView(
                        error: (viewModel.error ?? AppError.unknown("Failed to load profile")).localizedDescription,
                        retryAction: {
                            Task {
                                await viewModel.loadProfile(userId: userId)
                            }
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.profile?.name ?? "nav_tab_profile".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile = viewModel.profile, profile.id != appState.currentUser?.id, !appState.isGuest {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showReportSheet = true
                        } label: {
                            Label("profile_report_user".localized, systemImage: "exclamationmark.triangle")
                        }

                        if didBlock {
                            Label("profile_user_blocked".localized, systemImage: "hand.raised.fill")
                        } else {
                            Button(role: .destructive) {
                                showBlockConfirmation = true
                            } label: {
                                Label("profile_block_user".localized, systemImage: "hand.raised")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
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
        .confirmationDialog(
            "profile_block_user".localized,
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("profile_block_confirm".localized, role: .destructive) {
                Task { await blockUser() }
            }
            Button("common_cancel".localized, role: .cancel) {}
        } message: {
            Text("profile_block_confirmation_message".localized)
        }
        .alert("messaging_block_failed".localized, isPresented: Binding(
            get: { blockError != nil },
            set: { if !$0 { blockError = nil } }
        )) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(blockError ?? "")
        }
        .sheet(isPresented: $showReportSheet) {
            if let profile = viewModel.profile {
                ReportContentSheet(
                    context: .user(id: profile.id, name: profile.name)
                )
            }
        }
        .task {
            didBlock = MessageService.shared.isBlocked(userId)
            async let profileTask: Void = viewModel.loadProfile(userId: userId)
            async let badgesTask = LeaderboardService.shared.fetchUserBadges(userId: userId)
            await profileTask
            badges = (try? await badgesTask) ?? []
            BadgeCache.shared.store(badges: badges, for: userId)
        }
        .trackScreen("PublicProfile")
    }
    
    // MARK: - Header Section
    
    private func headerSection(profile: Profile) -> some View {
        VStack(spacing: 16) {
            AvatarView(
                imageUrl: profile.avatarUrl,
                name: profile.name,
                size: 120,
                badges: badges
            )
            
            Text(profile.name)
                .font(.naarsTitle)
                .fontWeight(.semibold)
            
            if let car = profile.car, !car.isEmpty {
                Text(car)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stats Section
    
    private func statsSection(rating: Double?, fulfilledCount: Int) -> some View {
        ProfileStatsCard(rating: rating, fulfilledCount: fulfilledCount)
    }
    
    // MARK: - Phone Section
    
    private func phoneSection(phoneNumber: String, profile: Profile) -> some View {
        let shouldAutoReveal = shouldAutoRevealPhone(for: profile)
        
        return VStack(spacing: 12) {
            if shouldAutoReveal || isPhoneRevealed {
                // Show full phone number
                VStack(spacing: 4) {
                    Text("profile_phone_number".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    Text(Validators.displayPhoneNumber(phoneNumber, masked: false))
                        .font(.naarsBody)
                        .fontWeight(.medium)
                }
            } else {
                // Show masked phone number with reveal button
                VStack(spacing: 8) {
                    Text(Validators.displayPhoneNumber(phoneNumber, masked: true))
                        .font(.naarsBody)
                        .fontWeight(.medium)
                    
                    Button {
                        // Light haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        
                        isPhoneRevealed = true
                    } label: {
                        Text("profile_reveal_number".localized)
                            .font(.naarsSubheadline)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reveal phone number")
                    .accessibilityHint("Double-tap to show the full phone number")
                }
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
        .onAppear {
            if shouldAutoReveal {
                isPhoneRevealed = true
            }
        }
    }
    
    // MARK: - Send Message Button
    
    @State private var selectedConversationId: UUID?
    
    private func sendMessageButton(userId: UUID) -> some View {
        Button {
            if appState.isGuest {
                guestRestrictionReason = .sendMessage
                showGuestPrompt = true
            } else {
                Task {
                    guard let currentUserId = appState.currentUser?.id else { return }
                    do {
                        let conversation = try await ConversationService.shared.getOrCreateDirectConversation(
                            userId: currentUserId,
                            otherUserId: userId
                        )
                        selectedConversationId = conversation.id
                    } catch {
                        AppLogger.error("profile", "Error creating conversation: \(error.localizedDescription)")
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "message.fill")
                Text("profile_send_message".localized)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.naarsPrimary)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .accessibilityLabel("Send message")
        .accessibilityHint("Double-tap to start a conversation with this person")
        .navigationDestination(item: $selectedConversationId) { conversationId in
            ConversationDetailView(conversationId: conversationId)
        }
    }
    
    // MARK: - Reviews Section
    
    private func reviewsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile_reviews".localized)
                .font(.naarsHeadline)
            
            if viewModel.reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "profile_no_reviews_yet".localized,
                    message: "profile_no_reviews_message".localized
                )
            } else {
                ForEach(viewModel.reviews) { review in
                    ReviewRow(review: review)
                }
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Block User

    private func blockUser() async {
        guard let currentUserId = appState.currentUser?.id else { return }
        isBlocking = true
        do {
            try await MessageService.shared.blockUser(
                blockerId: currentUserId,
                blockedId: userId,
                reason: "Blocked from profile"
            )
            didBlock = true
        } catch {
            blockError = error.localizedDescription
        }
        isBlocking = false
    }

    // MARK: - Helper Methods

    /// Determine if phone should be auto-revealed
    /// Auto-reveals if:
    /// - Viewing own profile
    /// - In active conversation with user
    /// - On same request (poster/claimer relationship)
    private func shouldAutoRevealPhone(for profile: Profile) -> Bool {
        // Check if viewing own profile
        if profile.id == appState.currentUser?.id {
            return true
        }
        
        // Phone number is currently revealed to any authenticated user viewing their own profile.
        // Future: also auto-reveal when in an active conversation or on the same request (poster/claimer relationship).
        
        return false
    }
}

// MARK: - Supporting Views

private typealias ReviewRow = ReviewRowView

#Preview {
    NavigationStack {
        PublicProfileView(userId: UUID())
            .environment(AppState())
    }
}

