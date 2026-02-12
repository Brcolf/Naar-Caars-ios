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
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
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
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showSettings = false
    @State private var showPendingUsersList = false
    @State private var showAdminPanel = false
    @State private var toastMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Constants.Spacing.lg) {
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
                            
                            notificationsSection()
                            
                            // Invite Codes Section
                            inviteCodesSection()
                            
                            // Reviews Section
                            reviewsSection()
                            
                            // Past Requests Section
                            pastRequestsSection()
                            
                            // Delete Account Section
                            deleteAccountSection()
                        } else if viewModel.isLoading {
                            LoadingView(message: "profile_loading".localized)
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
                                VStack(spacing: Constants.Spacing.md) {
                                    Image(systemName: "person.circle")
                                        .font(.system(size: 64))
                                        .foregroundColor(.secondary)
                                    
                                    Text("profile_not_signed_in".localized)
                                        .font(.naarsTitle2)
                                    
                                    Text("profile_sign_in_prompt".localized)
                                        .font(.naarsBody)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    PrimaryButton(
                                        title: "profile_retry".localized,
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
                .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
                    guard let intent else { return }
                    switch intent {
                    case .pendingUsers:
                        showPendingUsersList = true
                        navigationCoordinator.pendingIntent = nil
                    case .adminPanel:
                        showAdminPanel = true
                        navigationCoordinator.pendingIntent = nil
                    case .profile(let userId):
                        if userId == (appState.currentUser?.id ?? AuthService.shared.currentUserId) {
                            withAnimation(.easeInOut) {
                                proxy.scrollTo("profile.myProfile.reviewsSection", anchor: .top)
                            }
                        }
                        navigationCoordinator.pendingIntent = nil
                    default:
                        break
                    }
                }
            }
            .navigationTitle("profile_title".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Constants.Spacing.md) {
                        BellButton {
                            navigationCoordinator.pendingIntent = .notifications
                            AppLogger.info("profile", "Bell tapped")
                        }

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier("profile.settings")
                        
                        Button("profile_edit".localized) {
                            showEditProfile = true
                        }
                        .accessibilityIdentifier("profile.edit")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showPendingUsersList) {
                PendingUsersView()
            }
            .navigationDestination(isPresented: $showAdminPanel) {
                AdminPanelView()
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
            .alert("profile_sign_out".localized, isPresented: $showLogoutAlert) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("profile_sign_out".localized, role: .destructive) {
                    Task {
                        do {
                            try await AuthService.shared.signOut()
                            // AuthService already posts "userDidSignOut" notification
                            // AppLaunchManager will handle state change automatically
                            // No need to call performCriticalLaunch here
                            AppLogger.info("profile", "Sign out completed - state will update via notification")
                        } catch {
                            AppLogger.error("profile", "Sign out error: \(error.localizedDescription)")
                        }
                    }
                }
            } message: {
                Text("profile_sign_out_confirmation".localized)
            }
            .alert("profile_delete_account".localized, isPresented: $showDeleteAccountAlert) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("profile_delete".localized, role: .destructive) {
                    showDeleteConfirmation = true
                }
            } message: {
                Text("profile_delete_warning".localized)
            }
            .alert("profile_confirm_deletion".localized, isPresented: $showDeleteConfirmation) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("profile_delete_account".localized, role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
            } message: {
                Text("profile_confirm_deletion_message".localized)
            }
            .alert("profile_daily_limit_reached".localized, isPresented: $showRateLimitAlert) {
                Button("common_ok".localized, role: .cancel) {
                    rateLimitMessage = nil
                    viewModel.error = nil
                }
            } message: {
                Text(rateLimitMessage ?? "profile_invite_limit_message".localized)
            }
            .alert("profile_deletion_failed".localized, isPresented: $showDeleteError) {
                Button("common_ok".localized, role: .cancel) {
                    deleteErrorMessage = ""
                }
            } message: {
                Text("profile_deletion_failed_message".localized + "\n\n\(deleteErrorMessage)")
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
            .onChange(of: selectedPhoto) { _, newPhoto in
                guard let newPhoto else { return }
                Task {
                    guard let userId = appState.currentUser?.id ?? AuthService.shared.currentUserId else { return }
                    if let data = try? await newPhoto.loadTransferable(type: Data.self) {
                        do {
                            let _ = try await ProfileService.shared.uploadAvatar(imageData: data, userId: userId)
                            HapticManager.success()
                            toastMessage = "Photo updated"
                            await viewModel.loadProfile(userId: userId)
                        } catch {
                            AppLogger.error("profile", "Avatar upload failed: \(error.localizedDescription)")
                        }
                    }
                    selectedPhoto = nil
                }
            }
            .toast(message: $toastMessage)
            .trackScreen("MyProfile")
        }
    }
    
    // MARK: - Header Section
    
    private func headerSection(profile: Profile) -> some View {
        VStack(spacing: Constants.Spacing.md) {
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
            .accessibilityLabel("Profile photo for \(profile.name)")
            .accessibilityHint("Double-tap to change your profile photo")
            
            // Name and Email
            VStack(spacing: Constants.Spacing.xs) {
                Text(profile.name)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text(profile.email)
                    .font(.naarsSubheadline)
                    .foregroundColor(.secondary)
            }
            
            // Sign Out Button (directly under email)
            Button {
                showLogoutAlert = true
            } label: {
                Text("profile_sign_out".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.red)
            }
            .accessibilityIdentifier("profile.signout")
            .accessibilityLabel("Sign out")
            .accessibilityHint("Double-tap to sign out of your account")
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
        ProfileStatsCard(rating: rating, reviewCount: reviewCount, fulfilledCount: fulfilledCount)
    }
    
    // MARK: - Invite Codes Section
    
    private func inviteCodesSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("profile_invite_codes".localized)
                    .font(.naarsHeadline)
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
                    Text("profile_invite_neighbor".localized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Reviews Section
    
    private func reviewsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("profile_reviews".localized)
                    .font(.naarsHeadline)
                Spacer()
                if viewModel.reviews.count > 5 {
                    Button(showAllReviews ? "profile_show_less".localized : "profile_show_all".localized) {
                        withAnimation {
                            showAllReviews.toggle()
                        }
                    }
                    .font(.naarsCaption)
                    .foregroundColor(.naarsPrimary)
                }
            }
            
            if viewModel.reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "profile_no_reviews".localized,
                    message: "profile_no_reviews_message".localized,
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
        .background(Color.naarsCardBackground)
        .cornerRadius(12)
        .id("profile.myProfile.reviewsSection")
    }
    
    // MARK: - Past Requests Section
    
    private func pastRequestsSection() -> some View {
        NavigationLink(destination: PastRequestsView()) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.naarsPrimary)
                Text("profile_past_requests".localized)
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
            }
            .padding()
            .background(Color.naarsCardBackground)
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
                    Text("profile_delete_account".localized)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.naarsCardBackground)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDeletingAccount)
            
            if isDeletingAccount {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("profile_deleting_account".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
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
            AppLogger.error("profile", "Error deleting account: \(error.localizedDescription)")
            isDeletingAccount = false
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }
    
    // MARK: - Admin Panel Link
    
    private func adminPanelLink() -> some View {
        NavigationLink(destination: AdminPanelView()) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.naarsPrimary)
                Text("profile_admin_panel".localized)
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(12)
        }
        .accessibilityIdentifier("profile.adminPanel")
    }

    // MARK: - Notifications Link
    
    private func notificationsSection() -> some View {
        NavigationLink(destination: NotificationsListView()) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.naarsPrimary)
                Text("profile_notifications".localized)
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(12)
        }
        .accessibilityIdentifier("profile.notifications")
    }
    
}

// MARK: - Supporting Views

private struct InviteCodeRow: View {
    let codeWithInvitee: InviteCodeWithInvitee
    @State private var showCopiedToast = false
    @State private var showShareSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            HStack {
                Text(formatCode(codeWithInvitee.code))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                
                Spacer()
                
                if codeWithInvitee.isUsed {
                    Text("profile_invite_used".localized)
                        .font(.naarsCaption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.secondary)
                        .cornerRadius(8)
                } else {
                    Text("profile_invite_available".localized)
                        .font(.naarsCaption)
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
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    if let inviteeName = codeWithInvitee.inviteeName {
                        Text(String(format: "profile_invite_used_by".localized, inviteeName))
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let usedAt = codeWithInvitee.usedAt {
                        Text(usedAt.dateString)
                            .font(.naarsCaption)
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
                        HStack(spacing: Constants.Spacing.xs) {
                            Image(systemName: "doc.on.doc")
                            Text("profile_copy".localized)
                        }
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    }
                    
                    Button(action: {
                        showShareSheet = true
                    }) {
                        HStack(spacing: Constants.Spacing.xs) {
                            Image(systemName: "square.and.arrow.up")
                            Text("profile_share".localized)
                        }
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareMessage(codeWithInvitee.code)])
        }
        .overlay(
            Group {
                if showCopiedToast {
                    VStack {
                        Text("profile_copied".localized)
                            .font(.naarsCaption)
                            .padding(Constants.Spacing.sm)
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
        InviteCodeFormatter.formatCode(code)
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
        InviteCodeFormatter.generateShareMessage(code)
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

private typealias ReviewRow = ReviewRowView

#Preview {
    MyProfileView()
        .environmentObject(AppState())
}

