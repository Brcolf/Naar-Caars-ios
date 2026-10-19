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
    @Environment(AppState.self) private var appState
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var showEditProfile = false
    @State private var showLogoutAlert = false
    @State private var showImagePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    /// The A3 check (communities this deletion closes) starts when Delete Account is tapped, so its
    /// result is usually ready when the first alert's Delete is; nil while it runs.
    @State private var deletionCheckTask: Task<Void, Never>?
    @State private var deletionCheckNames: [String]?
    /// Set when the first alert's Delete was tapped before the check finished; the row shows the check meanwhile.
    @State private var deleteTappedWhileCheckingAt: Date?
    @State private var showDeleteClosesCommunitiesAlert = false
    @State private var deletionClosedCommunityNames: [String] = []
    @State private var showDeleteError = false
    @State private var showDeleteSuccess = false
    @State private var deleteErrorMessage = ""
    @State private var showSettings = false
    @State private var badges: [LeaderboardBadge] = []
    /// Requests to join opened from a notification (`.pendingUsers` / `.pendingMembers` intents).
    @State private var pendingMembersTarget: PendingMembersTarget?
    /// My communities, opened from the Profile row or from a `.myCommunities` / `.joinCommunity`
    /// intent: one destination, so an intent never pushes a second copy over the row's.
    @State private var showMyCommunities = false
    /// A community's reports opened from a `.communityReports` intent (`content_reported`).
    @State private var communityReportsTarget: UUID?
    /// A community's members opened from a `.communityMembers` intent (`membership_update`: made an owner).
    @State private var communityMembersTarget: UUID?
    @State private var showAdminPanel = false
    @State private var autoOpenAdminReports = false
    @State private var toastMessage: String? = nil
    @State private var photoUploadError: String? = nil
    @State private var activeProfileSheet: ProfileSheet?
    /// A `.profile` intent (a "review received" tap) arrived before the profile had loaded;
    /// the scroll to the reviews is done once the sections are on screen.
    @State private var scrollToReviewsWhenLoaded = false

    enum ProfileSheet: Identifiable {
        case reviews
        case savings
        case pastRequests
        case xpHistory

        var id: Int {
            switch self {
            case .reviews: return 0
            case .savings: return 1
            case .pastRequests: return 2
            case .xpHistory: return 3
            }
        }
    }

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
                                totalSavings: viewModel.totalSavings,
                                fulfilledCount: viewModel.fulfilledCount,
                                xp: viewModel.totalXP
                            )
                            
                            // Admin Panel Link (below stats): platform admins and admins of any community
                            if let adminScope = AdminPanelScope.initial(
                                isPlatformAdmin: profile.isAdmin,
                                administered: CommunityContext.shared.administeredCommunities
                            ) {
                                adminPanelLink(scope: adminScope)
                            }

                            myCommunitiesLink()

                            accountSettingsSection()

                            // Share App Section
                            shareAppSection()

                            // Badges Section
                            BadgeListSection(earnedBadges: badges)

                            // Reviews Section
                            reviewsSection()
                            
                            // Past Requests Section
                            pastRequestsSection()
                            
                            // Delete Account Section
                            deleteAccountSection()
                        } else if viewModel.isLoading {
                            LoadingView(message: "profile_loading".localized, isEmbedded: true)
                        } else {
                            // Check if we have a user ID to retry with
                            if let userId = AuthService.shared.currentUserId {
                                ErrorView(
                                    error: (viewModel.error ?? AppError.unknown("Failed to load profile")).localizedDescription,
                                    retryAction: {
                                        Task {
                                            await viewModel.loadProfile(userId: userId)
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
                                                if let userId = AuthService.shared.currentUserId {
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
                .background(Color.naarsBackground)
                .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
                    guard let intent else { return }
                    applyProfileIntent(intent, proxy: proxy)
                }
                .onAppear {
                    // Handle any intent set before this view appeared (e.g., during tab switch).
                    // `.profile` included: a "review received" tap on a first visit to this tab
                    // used to switch here without being applied, and the intent stayed set.
                    if let intent = navigationCoordinator.pendingIntent {
                        switch intent {
                        case .pendingUsers, .pendingMembers, .myCommunities, .joinCommunity, .adminPanel, .adminReports,
                             .communityReports, .communityMembers, .profile:
                            applyProfileIntent(intent, proxy: proxy)
                        default:
                            break
                        }
                    }
                }
                .onChange(of: viewModel.profile?.id) { _, loadedProfileId in
                    // Finishes a `.profile` intent that arrived before the profile had loaded
                    // (see applyProfileIntent).
                    guard scrollToReviewsWhenLoaded, loadedProfileId != nil else { return }
                    scrollToReviewsWhenLoaded = false
                    // One main-actor turn later, so the sections have been laid out.
                    Task { @MainActor in
                        withAnimation(.easeInOut) {
                            proxy.scrollTo("profile.myProfile.reviewsSection", anchor: .top)
                        }
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

                        Button("profile_edit".localized) {
                            showEditProfile = true
                        }
                        .accessibilityIdentifier("profile.edit")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $pendingMembersTarget) { target in
                PendingMembersView(target: target)
            }
            .navigationDestination(isPresented: $showMyCommunities) {
                MyCommunitiesView()
            }
            .navigationDestination(item: $communityReportsTarget) { communityId in
                CommunityReportsView(communityId: communityId, communityName: CommunityContext.shared.name(for: communityId))
            }
            .navigationDestination(item: $communityMembersTarget) { communityId in
                // Opened from a push: the role change may not be in the memberships yet.
                CommunityMembersView(target: CommunityMembersTarget(
                    communityId: communityId,
                    communityName: CommunityContext.shared.name(for: communityId),
                    refreshesRoleFirst: true
                ))
                // A push for another community while Members is open changes the item in place:
                // without a new identity the pushed screen keeps its first view model (its
                // @StateObject) and shows the first community. The same community keeps the screen.
                .id(communityId)
            }
            .navigationDestination(isPresented: $showAdminPanel) {
                AdminPanelView(autoOpenReports: autoOpenAdminReports, onCommunityArchived: { toastMessage = $0 })
                    .onDisappear { autoOpenAdminReports = false }
            }
            .refreshable {
                if let userId = AuthService.shared.currentUserId {
                    await viewModel.refreshProfile(userId: userId)
                }
            }
            .task(id: appState.currentUser?.id) {
                // Reactive: fires immediately if currentUser is set, or re-fires
                // the moment currentUser arrives after deferred loading completes.
                guard let userId = appState.currentUser?.id else { return }

                // loadProfile has an internal cache guard — returns immediately
                // if data for this user is already loaded, preventing the
                // thundering herd of 6+ RPCs on every tab switch.
                await viewModel.loadProfile(userId: userId)

                // Only fetch badges if we don't already have them for this user
                if badges.isEmpty {
                    badges = (try? await LeaderboardService.shared.fetchUserBadges(userId: userId)) ?? []
                    BadgeCache.shared.store(badges: badges, for: userId)
                }
            }
            .sheet(isPresented: $showEditProfile, onDismiss: {
                // Show what was just saved; the tab-switch guard would otherwise keep the old values.
                Task {
                    guard let userId = AuthService.shared.currentUserId else { return }
                    await viewModel.refreshProfile(userId: userId)
                }
            }) {
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
                Button("common_cancel".localized, role: .cancel) {
                    cancelDeletionCheck()
                }
                Button("profile_delete".localized, role: .destructive) {
                    continueDeletionAfterFirstAlert()
                }
            } message: {
                Text("profile_delete_warning".localized)
            }
            .alert("community_delete_closes_title".localized, isPresented: $showDeleteClosesCommunitiesAlert) {
                Button("common_cancel".localized, role: .cancel) {
                    deletionClosedCommunityNames = []
                }
                Button("community_delete_closes_confirm".localized, role: .destructive) {
                    deletionClosedCommunityNames = []
                    showDeleteConfirmation = true
                }
            } message: {
                Text("community_delete_closes_message".localized(
                    with: ListFormatter.localizedString(byJoining: deletionClosedCommunityNames)
                ))
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
            .alert("profile_deletion_failed".localized, isPresented: $showDeleteError) {
                Button("common_ok".localized, role: .cancel) {
                    deleteErrorMessage = ""
                }
            } message: {
                Text("profile_deletion_failed_message".localized + "\n\n\(deleteErrorMessage)")
            }
            .alert("profile_account_deleted".localized, isPresented: $showDeleteSuccess) {
                Button("common_ok".localized) {
                    Task {
                        try? await AuthService.shared.signOut()
                        await AppLaunchManager.shared.performCriticalLaunch()
                    }
                }
            } message: {
                Text("profile_account_deleted_message".localized)
            }
            .sheet(item: $activeProfileSheet) { sheet in
                switch sheet {
                case .reviews:
                    ReviewsSheet(reviews: viewModel.reviews)
                case .savings:
                    SavingsSheet()
                case .pastRequests:
                    // PastRequestsView is plain content (it is also pushed from the Past
                    // Requests row), so as a sheet it gets its stack and Close button here.
                    NavigationStack {
                        PastRequestsView(initialFilter: .helpedWith)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("common_close".localized) {
                                        activeProfileSheet = nil
                                    }
                                }
                            }
                    }
                case .xpHistory:
                    XPHistorySheet(totalXP: viewModel.totalXP)
                }
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                guard let newPhoto else { return }
                Task {
                    guard let userId = AuthService.shared.currentUserId else { return }
                    if let data = try? await newPhoto.loadTransferable(type: Data.self) {
                        do {
                            try await viewModel.uploadAvatar(imageData: data, userId: userId)
                            HapticManager.success()
                            toastMessage = "profile_photo_updated_toast".localized
                            await viewModel.refreshProfile(userId: userId)
                        } catch {
                            AppLogger.error("profile", "Avatar upload failed: \(error.localizedDescription)")
                            HapticManager.error()
                            photoUploadError = error.localizedDescription
                        }
                    }
                    selectedPhoto = nil
                }
            }
            .toast(message: $toastMessage)
            .errorBanner(message: $photoUploadError)
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
                    size: 100,
                    badges: badges
                )
            }
            .accessibilityLabel("profile_photo_accessibility".localized(with: profile.name))
            .accessibilityHint("profile_photo_hint".localized)
            
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
                // The frame sits inside the label so the whole 44-pt area is tappable
                Text("profile_sign_out".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsError)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("profile.signout")
            .accessibilityLabel("profile_sign_out".localized)
            .accessibilityHint("profile_sign_out_hint".localized)
        }
        .padding()
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedPhoto,
            matching: .images
        )
    }
    
    // MARK: - Stats Section
    
    private func statsSection(rating: Double?, totalSavings: Double, fulfilledCount: Int, xp: Int) -> some View {
        ProfileStatsCard(
            rating: rating,
            totalSavings: totalSavings,
            fulfilledCount: fulfilledCount,
            xp: xp,
            onRatingTap: { activeProfileSheet = .reviews },
            onSavingsTap: { activeProfileSheet = .savings },
            onFulfilledTap: { activeProfileSheet = .pastRequests },
            onXPTap: { activeProfileSheet = .xpHistory }
        )
    }
    
    // MARK: - Share App Section

    @State private var showShareSheet = false

    private func shareAppSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("profile_share_app_title".localized)
                    .font(.naarsHeadline)
                Spacer()
            }

            Button(action: {
                showShareSheet = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("profile_invite_friends".localized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .frame(maxWidth: .infinity)
                // A block inside a card takes the inset fill; the card's own color disappeared.
                .background(Color.naarsInsetBackground)
                .cornerRadius(Constants.Radius.sm)
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [
                    "profile_share_message".localized,
                    URL(string: Constants.URLs.appStore)!
                ] as [Any])
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(Constants.Radius.card)
    }
    
    // MARK: - Reviews Section
    
    private func reviewsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                if let userId = AuthService.shared.currentUserId {
                    AllReviewsView(userId: userId, totalReviewCount: viewModel.reviewCount)
                }
            } label: {
                HStack {
                    Text("profile_reviews".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                    Spacer()
                    if !viewModel.reviews.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(viewModel.reviews.isEmpty)
            
            if viewModel.reviews.isEmpty {
                EmptyStateView(
                    icon: "star",
                    title: "profile_no_reviews".localized,
                    message: "profile_no_reviews_message".localized,
                    customImage: "naars_Profile_icon"
                )
            } else {
                ForEach(Array(viewModel.reviews.prefix(5))) { review in
                    ReviewRow(review: review)
                }
            }
        }
        .padding()
        .background(Color.naarsCardBackground)
        .cornerRadius(Constants.Radius.card)
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
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(Constants.Radius.card)
        }
    }
    
    // MARK: - Delete Account Section
    
    private func deleteAccountSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                startDeletionFlow()
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                        .foregroundColor(.naarsError)
                    Text("profile_delete_account".localized)
                        .foregroundColor(.naarsError)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.naarsInsetBackground)
                .cornerRadius(Constants.Radius.sm)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isDeletingAccount || deleteTappedWhileCheckingAt != nil)
            .accessibilityIdentifier("profile.deleteAccount")

            if deleteTappedWhileCheckingAt != nil {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("community_delete_checking".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            if viewModel.isDeletingAccount {
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
        .cornerRadius(Constants.Radius.card)
    }
    
    /// Decision A3: before the final confirmation, name the communities this deletion closes.
    /// The check runs while the first alert is up, so the next alert is normally raised from that
    /// alert's Delete action, the same moment the final confirmation always was.
    private func startDeletionFlow() {
        cancelDeletionCheck()
        showDeleteAccountAlert = true
        deletionCheckTask = Task { @MainActor in
            let names = await viewModel.communitiesClosedByDeletion()
            guard !Task.isCancelled else { return }
            deletionCheckNames = names
            guard let tappedAt = deleteTappedWhileCheckingAt else { return }
            // Delete was tapped before the check finished: raise the next alert only once the first
            // one has finished going away, or SwiftUI can drop it and deletion would do nothing.
            let remaining = Constants.Animation.long - Date().timeIntervalSince(tappedAt)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            deleteTappedWhileCheckingAt = nil
            presentStepAfterFirstAlert(names)
        }
    }

    /// The first alert's Delete. An empty list goes straight to the final confirmation, as before.
    private func continueDeletionAfterFirstAlert() {
        if let names = deletionCheckNames {
            presentStepAfterFirstAlert(names)
        } else {
            deleteTappedWhileCheckingAt = Date()
        }
    }

    private func presentStepAfterFirstAlert(_ names: [String]) {
        deletionCheckTask = nil
        deletionCheckNames = nil
        if names.isEmpty {
            showDeleteConfirmation = true
        } else {
            deletionClosedCommunityNames = names
            showDeleteClosesCommunitiesAlert = true
        }
    }

    private func cancelDeletionCheck() {
        deletionCheckTask?.cancel()
        deletionCheckTask = nil
        deletionCheckNames = nil
        deleteTappedWhileCheckingAt = nil
    }

    private func deleteAccount() async {
        do {
            guard try await viewModel.deleteAccount() else { return }
            // Account deleted — show confirmation before signing out
            showDeleteSuccess = true
        } catch {
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }
    
    // MARK: - Admin Panel Link
    
    private func adminPanelLink(scope: AdminPanelScope) -> some View {
        NavigationLink(destination: AdminPanelView(
            scope: scope,
            communityName: CommunityContext.shared.name(for: scope.communityId),
            onCommunityArchived: { toastMessage = $0 }
        )) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.naarsPrimary)
                Text("profile_admin_panel".localized)
                    .font(.naarsHeadline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(Constants.Radius.card)
        }
        .accessibilityIdentifier("profile.adminPanel")
    }

    // MARK: - My Communities Link

    private func myCommunitiesLink() -> some View {
        let pendingTotal = CommunityContext.shared.administeredPendingTotal
        // A Button, not a NavigationLink: the row and every intent drive the one
        // `showMyCommunities` destination (setting it while already true pushes nothing).
        return Button {
            showMyCommunities = true
        } label: {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.naarsPrimary)
                    .accessibilityHidden(true)
                Text("community_my_profile_row".localized)
                    .font(.naarsHeadline)
                    .foregroundColor(.primary)
                Spacer()
                if pendingTotal > 0 {
                    NotificationBadge(count: pendingTotal)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
                    .accessibilityHidden(true)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(Constants.Radius.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("community_my_profile_row".localized)
        .accessibilityValue(pendingTotal > 0 ? "\(pendingTotal)" : "")
        .accessibilityIdentifier("profile.myCommunities")
    }

    // MARK: - Account Settings Link

    private func accountSettingsSection() -> some View {
        Button {
            showSettings = true
        } label: {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.naarsPrimary)
                Text("profile_account_settings".localized)
                    .font(.naarsHeadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
            }
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(Constants.Radius.card)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("profile.settings")
    }

    private func applyProfileIntent(_ intent: NavigationIntent, proxy: ScrollViewProxy) {
        switch intent {
        case .pendingUsers:
            // The platform admins' route opens the default community's Requests to join.
            pendingMembersTarget = .defaultCommunity
            navigationCoordinator.pendingIntent = nil
        case .pendingMembers(let communityId):
            pendingMembersTarget = .community(communityId, name: nil)
            navigationCoordinator.pendingIntent = nil
        case .myCommunities, .joinCommunity:
            // `.joinCommunity`: My communities opens Join from the saved code (PendingInviteStore).
            showMyCommunities = true
            navigationCoordinator.pendingIntent = nil
        case .adminPanel:
            showAdminPanel = true
            navigationCoordinator.pendingIntent = nil
        case .adminReports:
            autoOpenAdminReports = true
            showAdminPanel = true
            navigationCoordinator.pendingIntent = nil
        case .communityReports(let communityId):
            communityReportsTarget = communityId
            navigationCoordinator.pendingIntent = nil
        case .communityMembers(let communityId):
            communityMembersTarget = communityId
            navigationCoordinator.pendingIntent = nil
        case .profile(let userId):
            if userId == AuthService.shared.currentUserId {
                if viewModel.profile == nil {
                    // The sections are not on screen until the profile has loaded (first visit
                    // to the tab); a scroll requested now would do nothing. The onChange on the
                    // loaded profile does it instead. The intent is still cleared below.
                    scrollToReviewsWhenLoaded = true
                } else {
                    withAnimation(.easeInOut) {
                        proxy.scrollTo("profile.myProfile.reviewsSection", anchor: .top)
                    }
                }
            }
            navigationCoordinator.pendingIntent = nil
        default:
            break
        }
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
}

