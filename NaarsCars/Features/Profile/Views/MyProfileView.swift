//
//  MyProfileView.swift
//  NaarsCars
//
//  Current user's profile view with editing, reviews, and invite codes
//

import SwiftUI
import PhotosUI

/// View for displaying and managing current user's profile
struct MyProfileView: View {
    @StateObject private var viewModel = MyProfileViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showEditProfile = false
    @State private var showLogoutAlert = false
    @State private var showImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showRateLimitAlert = false
    @State private var rateLimitMessage: String?
    @State private var showInvitationWorkflow = false
    @State private var showAllReviews = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let profile = viewModel.profile {
                        // Header Section (with sign out)
                        headerSection(profile: profile)
                        
                        // Stats Section
                        statsSection(
                            rating: viewModel.averageRating,
                            reviewCount: viewModel.reviews.count,
                            fulfilledCount: viewModel.fulfilledCount
                        )
                        
                        // Admin Panel Link (below stats)
                        if profile.isAdmin {
                            adminPanelLink()
                        }
                        
                        // Invite Codes Section
                        inviteCodesSection()
                        
                        // Reviews Section
                        reviewsSection()
                        
                        // Past Requests Section
                        pastRequestsSection()
                        
                        // Delete Account Section
                        deleteAccountSection()
                    } else if viewModel.isLoading {
                        LoadingView(message: "Loading profile...")
                    } else {
                        // Check if we have a user ID to retry with
                        let hasUserId = appState.currentUser?.id != nil || AuthService.shared.currentUserId != nil
                        
                        if hasUserId {
                            ErrorView(
                                error: (viewModel.error ?? AppError.unknown("Failed to load profile")).localizedDescription,
                                retryAction: {
                                    // Try to get user ID from appState first, fallback to AuthService
                                    let userId: UUID?
                                    if let appStateUserId = appState.currentUser?.id {
                                        userId = appStateUserId
                                    } else if let authUserId = AuthService.shared.currentUserId {
                                        userId = authUserId
                                        // Update appState if we found a user via AuthService
                                        Task {
                                            await appState.checkAuthStatus()
                                        }
                                    } else {
                                        userId = nil
                                    }
                                    
                                    if let userId = userId {
                                        Task {
                                            await viewModel.loadProfile(userId: userId)
                                        }
                                    }
                                }
                            )
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 64))
                                    .foregroundColor(.secondary)
                                
                                Text("Not Signed In")
                                    .font(.naarsTitle2)
                                
                                Text("Please sign in to view your profile.")
                                    .font(.naarsBody)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                PrimaryButton(
                                    title: "Retry",
                                    action: {
                                        Task {
                                            await appState.checkAuthStatus()
                                            if let userId = appState.currentUser?.id ?? AuthService.shared.currentUserId {
                                                await viewModel.loadProfile(userId: userId)
                                            }
                                        }
                                    }
                                )
                                .padding(.horizontal)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("My Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        
                        Button("Edit") {
                            showEditProfile = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(appState)
            }
            .refreshable {
                // Try to get user ID from appState first, fallback to AuthService
                let userId: UUID?
                if let appStateUserId = appState.currentUser?.id {
                    userId = appStateUserId
                } else if let authUserId = AuthService.shared.currentUserId {
                    userId = authUserId
                } else {
                    userId = nil
                }
                
                if let userId = userId {
                    await viewModel.refreshProfile(userId: userId)
                }
            }
            .task {
                // Try to get user ID from appState first, fallback to AuthService
                let userId: UUID?
                if let appStateUserId = appState.currentUser?.id {
                    userId = appStateUserId
                } else if let authUserId = AuthService.shared.currentUserId {
                    userId = authUserId
                    // Update appState if we found a user via AuthService
                    Task {
                        await appState.checkAuthStatus()
                    }
                } else {
                    userId = nil
                }
                
                if let userId = userId {
                    await viewModel.loadProfile(userId: userId)
                } else {
                    viewModel.error = AppError.notAuthenticated
                }
            }
            .sheet(isPresented: $showEditProfile) {
                if let profile = viewModel.profile {
                    EditProfileView(profile: profile)
                }
            }
            .alert("Sign Out", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task {
                        do {
                            try await AuthService.shared.signOut()
                            // AuthService already posts "userDidSignOut" notification
                            // AppLaunchManager will handle state change automatically
                            // No need to call performCriticalLaunch here
                            print("✅ [MyProfileView] Sign out completed - state will update via notification")
                        } catch {
                            print("🔴 [MyProfileView] Sign out error: \(error.localizedDescription)")
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } message: {
                Text("This action cannot be undone. You will lose all information associated with your account, including any content you have generated such as rides, reviews, and posts.")
            }
            .alert("Confirm Account Deletion", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
            } message: {
                Text("Are you absolutely sure? This will permanently delete your account and all associated data. This action cannot be undone.")
            }
            .alert("Daily Limit Reached", isPresented: $showRateLimitAlert) {
                Button("OK", role: .cancel) {
                    rateLimitMessage = nil
                    viewModel.error = nil
                }
            } message: {
                Text(rateLimitMessage ?? "You can generate up to 5 invite codes per day. Try again tomorrow!")
            }
            .sheet(isPresented: $showInvitationWorkflow) {
                if let userId = appState.currentUser?.id {
                    InvitationWorkflowView(userId: userId) { code in
                        // Code generated - refresh profile to show new code
                        Task {
                            await viewModel.loadProfile(userId: userId)
                        }
                    }
                }
            }
            .trackScreen("MyProfile")
        }
    }
    
    // MARK: - Header Section
    
    private func headerSection(profile: Profile) -> some View {
        VStack(spacing: 16) {
            // Avatar
            Button {
                showImagePicker = true
            } label: {
                AvatarView(
                    imageUrl: profile.avatarUrl,
                    name: profile.name,
                    size: 100
                )
            }
            
            // Name and Email
            VStack(spacing: 4) {
                Text(profile.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(profile.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Sign Out Button (directly under email)
            Button {
                showLogoutAlert = true
            } label: {
                Text("Sign Out")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedPhoto,
            matching: .images
        )
    }
    
    // MARK: - Stats Section
    
    private func statsSection(rating: Double?, reviewCount: Int, fulfilledCount: Int) -> some View {
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
                Text("\(reviewCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Reviews")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    
    // MARK: - Invite Codes Section
    
    private func inviteCodesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎟️ Invite Codes")
                    .font(.headline)
                Spacer()
            }
            
            // Only show Generate button - no status messages
            Button(action: {
                if appState.currentUser?.id != nil {
                    showInvitationWorkflow = true
                }
            }) {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Invite a Neighbor")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Reviews Section
    
    private func reviewsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(.headline)
                Spacer()
                if viewModel.reviews.count > 5 {
                    Button(showAllReviews ? "Show Less" : "Show All") {
                        withAnimation {
                            showAllReviews.toggle()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            if viewModel.reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "No Reviews Yet",
                    message: "You haven't received any reviews yet.",
                    customImage: "naars_Profile_icon"
                )
            } else {
                let reviewsToShow = showAllReviews ? viewModel.reviews : Array(viewModel.reviews.prefix(5))
                ForEach(reviewsToShow) { review in
                    ReviewRow(review: review)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Past Requests Section
    
    private func pastRequestsSection() -> some View {
        NavigationLink(destination: PastRequestsView()) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.naarsPrimary)
                Text("Past Requests")
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Delete Account Section
    
    private func deleteAccountSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                showDeleteAccountAlert = true
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.red)
                    Text("Delete Account")
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDeletingAccount)
            
            if isDeletingAccount {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Deleting account...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func deleteAccount() async {
        guard let userId = appState.currentUser?.id else {
            return
        }
        
        isDeletingAccount = true
        
        do {
            try await ProfileService.shared.deleteAccount(userId: userId)
            // Account deleted - sign out and redirect
            try await AuthService.shared.signOut()
            await AppLaunchManager.shared.performCriticalLaunch()
        } catch {
            print("🔴 [MyProfileView] Error deleting account: \(error.localizedDescription)")
            isDeletingAccount = false
            // TODO: Show error alert to user
        }
    }
    
    // MARK: - Admin Panel Link
    
    private func adminPanelLink() -> some View {
        NavigationLink(destination: AdminPanelView()) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.naarsPrimary)
                Text("Admin Panel")
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
}

// MARK: - Supporting Views

private struct InviteCodeRow: View {
    let codeWithInvitee: InviteCodeWithInvitee
    @State private var showCopiedToast = false
    @State private var showShareSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatCode(codeWithInvitee.code))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                
                Spacer()
                
                if codeWithInvitee.isUsed {
                    Text("Used")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.secondary)
                        .cornerRadius(8)
                } else {
                    Text("Available")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                }
            }
            
            // Show invitee info if used
            if codeWithInvitee.isUsed {
                VStack(alignment: .leading, spacing: 4) {
                    if let inviteeName = codeWithInvitee.inviteeName {
                        Text("Used by: \(inviteeName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let usedAt = codeWithInvitee.usedAt {
                        Text(usedAt.dateString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Action buttons
            if !codeWithInvitee.isUsed {
                HStack(spacing: 12) {
                    Button(action: {
                        copyCode(codeWithInvitee.code)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        showShareSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareMessage(codeWithInvitee.code)])
        }
        .overlay(
            Group {
                if showCopiedToast {
                    VStack {
                        Text("Copied!")
                            .font(.caption)
                            .padding(8)
                            .background(Color(.systemGray))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        Spacer()
                    }
                    .padding()
                    .transition(.opacity)
                }
            },
            alignment: .top
        )
        .onChange(of: showCopiedToast) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCopiedToast = false
                    }
                }
            }
        }
    }
    
    private func formatCode(_ code: String) -> String {
        // Format based on code length
        // 10 chars (NC + 8): NC7X · 9K2A · BQ
        // 8 chars (NC + 6 legacy): NC7X · 9K2A
        let chars = Array(code)
        
        if code.count == 10 {
            // NC7X · 9K2A · BQ (groups of 4)
            return "\(String(chars[0...3])) · \(String(chars[4...7])) · \(String(chars[8...9]))"
        } else if code.count == 8 {
            // NC7X · 9K2A (groups of 4)
            return "\(String(chars[0...3])) · \(String(chars[4...7]))"
        } else {
            // Fallback: just return the code
            return code
        }
    }
    
    private func copyCode(_ code: String) {
        // Copy raw code without formatting
        UIPasteboard.general.string = code
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Show toast
        withAnimation {
            showCopiedToast = true
        }
    }
    
    private func generateShareMessage(_ code: String) -> String {
        // Generate share message with deep link containing embedded code
        // Deep link format: https://naarscars.com/signup?code=CODE
        // When user taps link, app opens and code is automatically populated
        let deepLink = "https://naarscars.com/signup?code=\(code)"
        let appStoreLink = "https://apps.apple.com/app/naars-cars" // TODO: Replace with actual App Store link when published
        
        return """
        Join me on Naar's Cars! 🚗
        
        Sign up here: \(deepLink)
        
        Or download the app and enter code: \(code)
        \(appStoreLink)
        """
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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
    MyProfileView()
        .environmentObject(AppState())
}

