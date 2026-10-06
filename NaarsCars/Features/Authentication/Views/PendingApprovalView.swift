//
//  PendingApprovalView.swift
//  NaarsCars
//
//  View shown when user is waiting for admin approval
//

import SwiftUI
import UserNotifications

/// View displayed when user account is pending admin approval
struct PendingApprovalView: View {
    @StateObject private var launchManager = AppLaunchManager.shared
    // Sign-out and delete-account actions, shared with the restricted and application screens
    @StateObject private var accountViewModel = BannedAccountViewModel()
    @State private var hasRequestedNotifications = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showNotificationPrompt = false
    @State private var isCheckingStatus = false
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        // Scrolls when the content is taller than the screen (small phones, large text sizes)
        // and otherwise keeps the centred layout: the stack is at least one screen tall.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Constants.Spacing.xl) {
                    Spacer(minLength: 0)

                    // Icon
                    Image(systemName: "hourglass")
                        .font(.system(size: 80))
                        .foregroundColor(.naarsPrimary)
                        .accessibilityHidden(true)

                    // Title — reviewer-safe copy
                    Text("pending_review_title".localized)
                        .font(.naarsTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Constants.Spacing.xl)
                        .accessibilityAddTraits(.isHeader)

                    // Description — reviewer-safe copy
                    Text("pending_review_body".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Constants.Spacing.xl)

                    // Notification permission prompt
                    if notificationStatus == .notDetermined && !hasRequestedNotifications {
                        notificationPromptCard
                    } else if notificationStatus == .authorized {
                        notificationEnabledBadge
                    }

                    Spacer(minLength: 0)

                    actionButtons
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Color.naarsBackground)
        .accessibilityIdentifier("pendingApproval.screen")
        .accountDeletionFlow(
            isConfirming: $showDeleteConfirmation,
            viewModel: accountViewModel,
            message: "account_delete_pre_approval_message".localized
        )
        .task {
            // Check notification status on appear
            await checkNotificationStatus()
            
            // Show notification prompt after a short delay if not determined
            if notificationStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                showNotificationPrompt = true
            }
            
            // Periodically check approval status (every 15 seconds)
            // This allows users to be automatically transitioned to the main app when approved
            await startPeriodicApprovalCheck()
        }
    }
    
    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: Constants.Spacing.ms) {
            // Refresh Status
            PrimaryButton(
                title: "pending_review_refresh".localized,
                action: { refreshStatus() },
                isLoading: isCheckingStatus,
                isDisabled: isCheckingStatus
            )
            .accessibilityIdentifier("pendingApproval.refresh")

            // Outcome of the last manual check; without it the button appeared to do nothing
            if let statusMessage {
                Text(statusMessage)
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pendingApproval.statusMessage")
            }

            // Contact Support
            SecondaryButton(title: "pending_review_contact_support".localized) {
                if let url = URL(string: "mailto:naarscars@gmail.com") {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityIdentifier("pendingApproval.contactSupport")

            // Sign Out
            AccountTextAction(
                title: "pending_review_sign_out".localized,
                isBusy: accountViewModel.isSigningOut
            ) {
                Task { await accountViewModel.signOut() }
            }
            .disabled(accountViewModel.isDeletingAccount)
            .accessibilityIdentifier("pendingApproval.signOut")

            // Delete Account. Low emphasis, but it has to be here: a pending user cannot
            // reach Settings, and the account already exists (Guideline 5.1.1(v)).
            AccountTextAction(
                title: "profile_delete_account".localized,
                isDestructive: true,
                isBusy: accountViewModel.isDeletingAccount
            ) {
                showDeleteConfirmation = true
            }
            .disabled(accountViewModel.isSigningOut)
            .accessibilityIdentifier("pendingApproval.deleteAccount")
        }
        .padding(.horizontal, Constants.Spacing.xl)
        .padding(.bottom, Constants.Spacing.lg)
    }

    /// Manual status check with visible feedback
    private func refreshStatus() {
        guard !isCheckingStatus else { return }
        Task {
            isCheckingStatus = true
            statusMessage = nil
            let isApproved = await checkApprovalDirectly()
            isCheckingStatus = false

            if isApproved {
                launchManager.state = .ready(.authenticated)
                return
            }

            // The check answers "not approved" for a failed request too; connectivity is the
            // only signal available here to tell the two apart. Read through the view model,
            // which has had the path monitor running since this screen appeared.
            let message = accountViewModel.isOnline
                ? "pending_review_status_still_pending".localized
                : "pending_review_status_check_failed".localized
            statusMessage = message
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    // MARK: - Notification UI Components

    private var notificationPromptCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.naarsTitle2)
                    .foregroundColor(.naarsPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("pending_approval_enable_notifications".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.primary)
                    
                    Text("pending_approval_notifications_description".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: {
                Task {
                    await requestNotificationPermission()
                }
            }) {
                Text("pending_approval_enable_button".localized)
                    .font(.naarsSubheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.naarsPrimary)
                    .cornerRadius(Constants.Radius.sm)
            }
            .accessibilityIdentifier("pendingApproval.enableNotifications")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(Constants.Radius.card)
        .padding(.horizontal, 32)
        .opacity(showNotificationPrompt ? 1 : 0)
        .animation(.easeIn(duration: 0.3), value: showNotificationPrompt)
    }
    
    private var notificationEnabledBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.naarsSuccess)
            
            Text("pending_approval_notifications_enabled".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Notification Methods
    
    private func checkNotificationStatus() async {
        let status = await PushNotificationService.shared.checkAuthorizationStatus()
        await MainActor.run {
            notificationStatus = status
        }
    }
    
    private func requestNotificationPermission() async {
        hasRequestedNotifications = true
        
        let granted = await PushNotificationService.shared.requestPermission()
        
        await MainActor.run {
            notificationStatus = granted ? .authorized : .denied
        }
        
        // If granted and we have a user ID, register for remote notifications
        if granted {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    /// Start periodic checks for approval status
    /// Checks every 30 seconds to detect when user is approved
    private func startPeriodicApprovalCheck() async {
        // Initial check after 10 seconds (give server time to process approval)
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        
        // Then check every 30 seconds (reduced frequency to avoid loops)
        while !Task.isCancelled {
            // Check approval status directly without triggering full launch flow
            // This prevents state oscillation and request storms
            let isApproved = await checkApprovalDirectly()
            
            if isApproved {
                // User is now approved - transition to authenticated state
                launchManager.state = .ready(.authenticated)
                return // Exit the loop
            }
            
            // Wait 30 seconds before next check
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
        }
    }
    
    /// Check approval status directly without triggering full launch flow
    private func checkApprovalDirectly() async -> Bool {
        // Use AppLaunchManager's lightweight check (doesn't change state)
        return await launchManager.checkApprovalStatusOnly()
    }
}

#Preview {
    PendingApprovalView()
}
