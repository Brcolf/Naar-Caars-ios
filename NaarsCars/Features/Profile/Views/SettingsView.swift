//
//  SettingsView.swift
//  NaarsCars
//
//  Settings view with biometric authentication and notification preferences
//

import SwiftUI
import UserNotifications
import AuthenticationServices
internal import Combine

/// Settings view for biometric authentication and notification preferences
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    private let biometricService = BiometricService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                // Biometric Authentication Section
                if biometricService.isBiometricsAvailable {
                    Section {
                        Toggle(isOn: $viewModel.biometricsEnabled) {
                            Label {
                                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                    Text(String(format: "settings_use_biometric".localized, biometricService.biometricType.displayName))
                                        .font(.naarsBody)
                                    Text("settings_biometric_unlock".localized)
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: biometricService.biometricType.iconName)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .onChange(of: viewModel.biometricsEnabled) { _, newValue in
                            HapticManager.selectionChanged()
                            Task {
                                await viewModel.handleBiometricsToggle(newValue)
                            }
                        }
                        
                        if viewModel.biometricsEnabled {
                            Toggle(isOn: $viewModel.requireBiometricsOnLaunch) {
                                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                    Text("settings_require_on_launch".localized)
                                        .font(.naarsBody)
                                    Text("settings_lock_when_returning".localized)
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onChange(of: viewModel.requireBiometricsOnLaunch) { _, newValue in
                                HapticManager.selectionChanged()
                                viewModel.updateRequireOnLaunch(newValue)
                            }
                        }
                    } header: {
                        Text("settings_biometric_auth".localized)
                    } footer: {
                        if viewModel.biometricsEnabled && viewModel.requireBiometricsOnLaunch {
                            Text("settings_lock_after_background".localized)
                                .font(.naarsCaption)
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.naarsWarning)
                            Text("settings_biometric_not_available".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("settings_biometric_auth".localized)
                    }
                }
                
                // Notification Settings Section
                NotificationSettingsSection(viewModel: viewModel)
                
                // Account Linking Section
                AccountSettingsSection(viewModel: viewModel)
                
                // Messaging Settings Section
                MessagingSettingsSection(viewModel: viewModel)
                
                // Language Settings Section
                Section {
                    NavigationLink(destination: LanguageSettingsView()) {
                        Label {
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text("settings_language".localized)
                                    .font(.naarsBody)
                                Text(LocalizationManager.supportedLanguages.first(where: { $0.code == LocalizationManager.shared.appLanguage })?.localizedName ?? "settings_system_default".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "globe")
                                .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    Text("settings_general".localized)
                } footer: {
                    Text("settings_change_language_footer".localized)
                        .font(.naarsCaption)
                }
                
                // Appearance Section
                AppearanceSettingsSection(viewModel: viewModel)
                
                // Privacy Section
                PrivacySettingsSection(viewModel: viewModel)
                
                // Debug Section (only in DEBUG builds)
                #if DEBUG
                Section {
                    NavigationLink(destination: NotificationDiagnosticsView()) {
                        Label {
                            Text("Notification Diagnostics")
                                .foregroundColor(.primary)
                        } icon: {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Button(action: {
                        viewModel.triggerTestCrash()
                    }) {
                        Label {
                            Text("Test Crash")
                                .foregroundColor(.red)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Button(action: {
                        viewModel.triggerTestNonFatalError()
                    }) {
                        Label {
                            Text("Test Non-Fatal Error")
                                .foregroundColor(.naarsWarning)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.naarsWarning)
                        }
                    }
                } header: {
                    Text("Debug (Dev Only)")
                } footer: {
                    Text("These options are only visible in debug builds for testing crash reporting.")
                        .font(.naarsCaption)
                }

                Section {
                    Toggle(isOn: $viewModel.performanceInstrumentationEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text("Performance Instrumentation")
                                    .foregroundColor(.primary)
                                Text("Enable operation latency metrics and SLO telemetry.")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "speedometer")
                                .foregroundColor(.orange)
                        }
                    }
                    .onChange(of: viewModel.performanceInstrumentationEnabled) { _, enabled in
                        viewModel.updatePerformanceInstrumentation(enabled)
                    }

                    Toggle(isOn: $viewModel.metricKitEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text("MetricKit Payload Collection")
                                    .foregroundColor(.primary)
                                Text("Collect OS hang/crash diagnostics payloads.")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.red)
                        }
                    }
                    .onChange(of: viewModel.metricKitEnabled) { _, enabled in
                        viewModel.updateMetricKitEnabled(enabled)
                    }

                    Toggle(isOn: $viewModel.verbosePerformanceLogsEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                Text("Verbose Performance Logs")
                                    .foregroundColor(.primary)
                                Text("Increase performance logging detail in debug sessions.")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .foregroundColor(.indigo)
                        }
                    }
                    .onChange(of: viewModel.verbosePerformanceLogsEnabled) { _, enabled in
                        viewModel.updateVerbosePerformanceLogs(enabled)
                    }
                } header: {
                    Text("Performance Flags")
                } footer: {
                    Text("Debug-only controls for staged performance rollouts.")
                        .font(.naarsCaption)
                }
                #endif
                
                // About Section with Supreme Leader
                Section {
                    VStack(spacing: Constants.Spacing.md) {
                        // Supreme Leader Character
                        Image("SupremeLeader")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .accessibilityLabel("Naar's Cars Supreme Leader")
                        
                        // App Name and Tagline
                        VStack(spacing: Constants.Spacing.xs) {
                            Text("app_name".localized)
                                .font(.naarsTitle3)
                                .fontWeight(.bold)
                            
                        Text("settings_tagline".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .italic()
                        }
                        
                        // Version
                        Text(String(format: "settings_version_format".localized, Bundle.main.appVersion))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Community Guidelines Link
                    NavigationLink(destination: CommunityGuidelinesView(showDismissButton: false)) {
                        Label {
                            Text("settings_community_guidelines".localized)
                                .font(.naarsBody)
                        } icon: {
                            Image(systemName: "doc.text")
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    // Privacy Policy Link
                    Link(destination: URL(string: Constants.URLs.privacyPolicy)!) {
                        Label {
                            HStack {
                                Text("settings_privacy_policy".localized)
                                    .font(.naarsBody)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    // Terms of Service Link
                    Link(destination: URL(string: Constants.URLs.termsOfService)!) {
                        Label {
                            HStack {
                                Text("settings_terms_of_service".localized)
                                    .font(.naarsBody)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.plaintext")
                                .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    Text("settings_about".localized)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("settings_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("settings_done".localized) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadSettings()
            }
            .alert("common_error".localized, isPresented: $viewModel.showError) {
                Button("common_ok".localized, role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "common_error".localized)
            }
            .alert("settings_link_apple_id_alert_title".localized, isPresented: $viewModel.showLinkAppleAlert) {
                Button("settings_link".localized) {
                    viewModel.startAppleLinking = true
                }
                Button("common_cancel".localized, role: .cancel) {}
            } message: {
                Text("settings_link_apple_id_alert_message".localized)
            }
            .sheet(isPresented: $viewModel.startAppleLinking) {
                NavigationStack {
                    AppleSignInLinkView(
                        onCompletion: { credential in
                            Task {
                                await viewModel.linkAppleAccount(credential: credential)
                            }
                        }
                    )
                    .navigationTitle("settings_link_apple_id_alert_title".localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("common_cancel".localized) {
                                viewModel.startAppleLinking = false
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var biometricsEnabled = false
    @Published var requireBiometricsOnLaunch = false
    @Published var pushNotificationsEnabled = false
    @Published var notifyRideUpdates = true
    @Published var notifyMessages = true
    @Published var notifyAnnouncements = true
    @Published var notifyNewRequests = true
    @Published var notifyQaActivity = true
    @Published var notifyReviewReminders = true
    @Published var notifyTownHall = true
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var isAppleLinked = false
    @Published var showLinkAppleAlert = false
    @Published var startAppleLinking = false
    @Published var selectedTheme: ThemeMode = .system
    @Published var crashReportingEnabled = true
    
    // Messaging settings
    @Published var sendReadReceipts = true
    @Published var showTypingIndicators = true
    @Published var showLinkPreviews = true
    @Published var autoDownloadMedia = true

#if DEBUG
    @Published var performanceInstrumentationEnabled = true
    @Published var metricKitEnabled = true
    @Published var verbosePerformanceLogsEnabled = false
#endif
    
    private let biometricService = BiometricService.shared
    private let biometricPreferences = BiometricPreferences.shared
    private let pushNotificationService = PushNotificationService.shared
    private let themeManager = ThemeManager.shared
    private let crashReportingService = CrashReportingService.shared
    
    func loadSettings() async {
        // Load biometric preferences
        biometricsEnabled = biometricPreferences.isBiometricsEnabled
        requireBiometricsOnLaunch = biometricPreferences.requireBiometricsOnLaunch
        
        // Load push notification status
        let authStatus = await pushNotificationService.checkAuthorizationStatus()
        pushNotificationsEnabled = authStatus == .authorized
        
        // Check if Apple ID is linked
        isAppleLinked = UserDefaults.standard.string(forKey: "appleUserIdentifier") != nil
        
        // Load theme preference
        selectedTheme = themeManager.currentTheme
        
        // Load crash reporting preference
        crashReportingEnabled = crashReportingService.isEnabled
        
        // Load notification preferences from profile
        if let userId = AuthService.shared.currentUserId,
           let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
            notifyRideUpdates = profile.notifyRideUpdates
            notifyMessages = profile.notifyMessages
            notifyAnnouncements = true
            notifyNewRequests = true
            notifyQaActivity = profile.notifyQaActivity
            notifyReviewReminders = profile.notifyReviewReminders
            notifyTownHall = profile.notifyTownHall
            
            if profile.notifyAnnouncements == false || profile.notifyNewRequests == false {
                try? await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyAnnouncements: true,
                    notifyNewRequests: true
                )
            }
        }
        
        // Load messaging preferences from UserDefaults
        sendReadReceipts = UserDefaults.standard.object(forKey: "messaging_sendReadReceipts") as? Bool ?? true
        showTypingIndicators = UserDefaults.standard.object(forKey: "messaging_showTypingIndicators") as? Bool ?? true
        showLinkPreviews = UserDefaults.standard.object(forKey: "messaging_showLinkPreviews") as? Bool ?? true
        autoDownloadMedia = UserDefaults.standard.object(forKey: "messaging_autoDownloadMedia") as? Bool ?? true

#if DEBUG
        performanceInstrumentationEnabled = FeatureFlags.performanceInstrumentationEnabled
        metricKitEnabled = FeatureFlags.metricKitEnabled
        verbosePerformanceLogsEnabled = FeatureFlags.verbosePerformanceLogsEnabled
#endif
    }
    
    func updateMessagingPreference(_ type: MessagingPreferenceType, enabled: Bool) {
        switch type {
        case .sendReadReceipts:
            UserDefaults.standard.set(enabled, forKey: "messaging_sendReadReceipts")
        case .showTypingIndicators:
            UserDefaults.standard.set(enabled, forKey: "messaging_showTypingIndicators")
        case .showLinkPreviews:
            UserDefaults.standard.set(enabled, forKey: "messaging_showLinkPreviews")
        case .autoDownloadMedia:
            UserDefaults.standard.set(enabled, forKey: "messaging_autoDownloadMedia")
        }
    }
    
    func updateTheme(_ theme: ThemeMode) {
        themeManager.setTheme(theme)
    }
    
    func updateCrashReporting(_ enabled: Bool) {
        crashReportingService.setCrashReportingEnabled(enabled)
        CrashReportingService.shared.logAction("crash_reporting_toggled", parameters: ["enabled": enabled])
    }
    
    #if DEBUG
    func updatePerformanceInstrumentation(_ enabled: Bool) {
        FeatureFlags.setPerformanceInstrumentationEnabled(enabled)
    }

    func updateMetricKitEnabled(_ enabled: Bool) {
        FeatureFlags.setMetricKitEnabled(enabled)
    }

    func updateVerbosePerformanceLogs(_ enabled: Bool) {
        FeatureFlags.setVerbosePerformanceLogsEnabled(enabled)
    }

    func triggerTestCrash() {
        crashReportingService.forceCrash()
    }
    
    func triggerTestNonFatalError() {
        crashReportingService.recordTestError()
        errorMessage = "Test non-fatal error recorded. Check Firebase Console."
        showError = true
    }
    #endif
    
    func handleBiometricsToggle(_ enabled: Bool) async {
        if enabled {
            // Verify biometrics before enabling
            do {
                let success = try await biometricService.authenticate(
                    reason: "Verify your identity to enable \(biometricService.biometricType.displayName)"
                )
                
                if success {
                    biometricPreferences.isBiometricsEnabled = true
                    biometricPreferences.recordAuthentication()
                    biometricsEnabled = true
                } else {
                    biometricsEnabled = false
                }
            } catch {
                biometricsEnabled = false
                if let biometricError = error as? BiometricError,
                   case .cancelled = biometricError {
                    // User cancelled - don't show error
                } else {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        } else {
            biometricPreferences.isBiometricsEnabled = false
            biometricPreferences.requireBiometricsOnLaunch = false
            requireBiometricsOnLaunch = false
        }
    }
    
    func updateRequireOnLaunch(_ enabled: Bool) {
        biometricPreferences.requireBiometricsOnLaunch = enabled
    }
    
    func handlePushNotificationToggle(_ enabled: Bool) async {
        if enabled {
            let granted = await pushNotificationService.requestPermission()
            if granted {
                pushNotificationsEnabled = true
                // Device token registration is handled automatically by AppDelegate
                // when didRegisterForRemoteNotificationsWithDeviceToken is called
            } else {
                pushNotificationsEnabled = false
                errorMessage = "settings_push_denied".localized
                showError = true
            }
        } else {
            pushNotificationsEnabled = false
            // Note: We can't revoke system permission, but we can stop registering tokens
            // The user would need to disable in iOS Settings
        }
    }
    
    func updateNotificationPreference(_ type: NotificationPreferenceType, enabled: Bool) async {
        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "settings_user_not_logged_in".localized
            showError = true
            return
        }
        
        do {
            switch type {
            case .rideUpdates:
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyRideUpdates: enabled
                )
                notifyRideUpdates = enabled
            case .messages:
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyMessages: enabled
                )
                notifyMessages = enabled
            case .announcements:
                notifyAnnouncements = true
            case .newRequests:
                notifyNewRequests = true
            case .qaActivity:
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyQaActivity: enabled
                )
                notifyQaActivity = enabled
            case .reviewReminders:
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyReviewReminders: enabled
                )
                notifyReviewReminders = enabled
            case .townHall:
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyTownHall: enabled
                )
                notifyTownHall = enabled
            }
            
            // Refresh profile cache
            await CacheManager.shared.invalidateProfile(id: userId)
        } catch {
            errorMessage = String(format: "settings_notification_update_failed".localized, error.localizedDescription)
            showError = true
            // Revert toggle
            switch type {
            case .rideUpdates: notifyRideUpdates = !enabled
            case .messages: notifyMessages = !enabled
            case .announcements: notifyAnnouncements = true
            case .newRequests: notifyNewRequests = true
            case .qaActivity: notifyQaActivity = !enabled
            case .reviewReminders: notifyReviewReminders = !enabled
            case .townHall: notifyTownHall = !enabled
            }
        }
    }
    
    func linkAppleAccount(credential: ASAuthorizationAppleIDCredential) async {
        do {
            try await AuthService.shared.linkAppleAccount(credential: credential)
            isAppleLinked = true
            startAppleLinking = false
            // Refresh settings to update UI
            await loadSettings()
        } catch {
            errorMessage = String(format: "settings_link_apple_failed".localized, error.localizedDescription)
            showError = true
        }
    }
}

enum NotificationPreferenceType {
    case rideUpdates
    case messages
    case announcements
    case newRequests
    case qaActivity
    case reviewReminders
    case townHall
}

enum MessagingPreferenceType {
    case sendReadReceipts
    case showTypingIndicators
    case showLinkPreviews
    case autoDownloadMedia
}

// MARK: - Notification Diagnostics

struct NotificationDiagnosticsView: View {
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var token: String?
    @State private var lastPayload: String?
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let pushService = PushNotificationService.shared
    
    var body: some View {
        Form {
            Section("Authorization") {
                Text("Status: \(authorizationStatusLabel)")
            }
            
            Section("APNs Token") {
                if let token = token {
                    Text(token)
                        .font(.naarsFootnote)
                        .textSelection(.enabled)
                } else {
                    Text("settings_no_token".localized)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Last Push Payload") {
                if let lastPayload = lastPayload {
                    Text(lastPayload)
                        .font(.naarsFootnote)
                        .textSelection(.enabled)
                } else {
                    Text("settings_no_payload".localized)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Notification Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let settings = await notificationCenter.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            token = pushService.storedDeviceTokenString()
            lastPayload = pushService.lastPushPayloadDescription()
        }
    }
    
    private var authorizationStatusLabel: String {
        switch authorizationStatus {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Blocked Users View

/// View for managing blocked users
struct BlockedUsersView: View {
    @State private var blockedUsers: [BlockedUser] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showUnblockConfirmation = false
    @State private var userToUnblock: BlockedUser?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("common_loading".localized)
            } else if blockedUsers.isEmpty {
                VStack(spacing: Constants.Spacing.md) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("settings_no_blocked_users".localized)
                        .font(.naarsHeadline)
                    
                    Text("settings_blocked_users_empty".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(blockedUsers) { blockedUser in
                        HStack(spacing: 12) {
                            // Avatar
                            AvatarView(
                                imageUrl: blockedUser.blockedAvatarUrl,
                                name: blockedUser.blockedName,
                                size: 44
                            )
                            
                            // Name and blocked date
                            VStack(alignment: .leading, spacing: 2) {
                                Text(blockedUser.blockedName)
                                    .font(.naarsBody)
                                
                                Text(String(format: "settings_blocked_date".localized, blockedUser.blockedAt.timeAgoString))
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Unblock button
                            Button("settings_unblock".localized) {
                                userToUnblock = blockedUser
                                showUnblockConfirmation = true
                            }
                            .font(.naarsSubheadline)
                            .foregroundColor(.naarsPrimary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("settings_blocked_users".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBlockedUsers()
        }
        .alert("settings_unblock_user".localized, isPresented: $showUnblockConfirmation) {
            Button("common_cancel".localized, role: .cancel) {
                userToUnblock = nil
            }
            Button("settings_unblock".localized) {
                if let user = userToUnblock {
                    Task {
                        await unblockUser(user)
                    }
                }
                userToUnblock = nil
            }
        } message: {
            if let user = userToUnblock {
                Text(String(format: "settings_unblock_confirmation".localized, user.blockedName))
            }
        }
    }
    
    private func loadBlockedUsers() async {
        guard let userId = AuthService.shared.currentUserId else {
            isLoading = false
            return
        }
        
        do {
            blockedUsers = try await MessageService.shared.getBlockedUsers(userId: userId)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    private func unblockUser(_ blockedUser: BlockedUser) async {
        guard let userId = AuthService.shared.currentUserId else { return }
        
        do {
            try await MessageService.shared.unblockUser(blockerId: userId, blockedId: blockedUser.blockedId)
            
            // Remove from local list
            blockedUsers.removeAll { $0.blockedId == blockedUser.blockedId }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

#Preview("Blocked Users") {
    NavigationStack {
        BlockedUsersView()
    }
}
