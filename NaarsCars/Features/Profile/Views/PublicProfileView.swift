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
    @EnvironmentObject var appState: AppState
    @State private var isPhoneRevealed = false
    
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
                    
                    // Phone Section (if available)
                    if let phoneNumber = profile.phoneNumber {
                        phoneSection(phoneNumber: phoneNumber, profile: profile)
                    }
                    
                    // Send Message Button (if not own profile)
                    if profile.id != appState.currentUser?.id {
                        sendMessageButton(userId: profile.id)
                    }
                    
                    // Reviews Section
                    reviewsSection()
                } else if viewModel.isLoading {
                    LoadingView(message: "Loading profile...")
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
        .navigationTitle(viewModel.profile?.name ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProfile(userId: userId)
        }
    }
    
    // MARK: - Header Section
    
    private func headerSection(profile: Profile) -> some View {
        VStack(spacing: 16) {
            AvatarView(
                imageUrl: profile.avatarUrl,
                name: profile.name,
                size: 120
            )
            
            Text(profile.name)
                .font(.title)
                .fontWeight(.semibold)
            
            if let car = profile.car, !car.isEmpty {
                Text(car)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stats Section
    
    private func statsSection(rating: Double?, fulfilledCount: Int) -> some View {
        HStack(spacing: 32) {
            VStack {
                if let rating = rating {
                    Text(String(format: "%.1f", rating))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("No Rating")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            VStack {
                Text("\(fulfilledCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Fulfilled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Phone Section
    
    private func phoneSection(phoneNumber: String, profile: Profile) -> some View {
        let shouldAutoReveal = shouldAutoRevealPhone(for: profile)
        
        return VStack(spacing: 12) {
            if shouldAutoReveal || isPhoneRevealed {
                // Show full phone number
                VStack(spacing: 4) {
                    Text("Phone Number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(Validators.displayPhoneNumber(phoneNumber, masked: false))
                        .font(.body)
                        .fontWeight(.medium)
                }
            } else {
                // Show masked phone number with reveal button
                VStack(spacing: 8) {
                    Text(Validators.displayPhoneNumber(phoneNumber, masked: true))
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Button {
                        // Light haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        
                        isPhoneRevealed = true
                    } label: {
                        Text("Reveal Number")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            if shouldAutoReveal {
                isPhoneRevealed = true
            }
        }
    }
    
    // MARK: - Send Message Button
    
    @State private var navigateToConversation: UUID?
    
    private func sendMessageButton(userId: UUID) -> some View {
        Button {
            Task {
                guard let currentUserId = appState.currentUser?.id else { return }
                do {
                    let conversation = try await MessageService.shared.getOrCreateDirectConversation(
                        userId: currentUserId,
                        otherUserId: userId
                    )
                    navigateToConversation = conversation.id
                } catch {
                    print("🔴 Error creating conversation: \(error.localizedDescription)")
                }
            }
        } label: {
            HStack {
                Image(systemName: "message.fill")
                Text("Send Message")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.naarsPrimary)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .navigationDestination(item: $navigateToConversation) { conversationId in
            ConversationDetailView(conversationId: conversationId)
        }
    }
    
    // MARK: - Reviews Section
    
    private func reviewsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews")
                .font(.headline)
            
            if viewModel.reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Reviews Yet",
                    message: "This user hasn't received any reviews yet."
                )
            } else {
                ForEach(viewModel.reviews) { review in
                    ReviewRow(review: review)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        
        // TODO: Check if in active conversation
        // TODO: Check if on same request
        
        return false
    }
}

// MARK: - Supporting Views

private struct ReviewRow: View {
    let review: Review
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Star rating
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= review.rating ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
                
                Spacer()
                
                Text(review.createdAt.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let comment = review.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        PublicProfileView(userId: UUID())
            .environmentObject(AppState())
    }
}

