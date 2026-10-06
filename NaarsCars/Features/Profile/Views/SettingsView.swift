//
//  SettingsView.swift
//  NaarsCars
//
//  Settings view with biometric authentication and notification preferences
//

import SwiftUI
import MessageUI
import UserNotifications
import AuthenticationServices
internal import Combine

/// Settings view for biometric authentication and notification preferences
struct SettingsView: View {
    @Environment(AppState.self) var appState
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
                                    .foregroundColor(.naarsPrimary)
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
                                Text(LocalizationManager.supportedLanguages.first(where: { $0.code != "system" && $0.code == LocalizationManager.shared.appLanguage })?.localizedName ?? "settings_system_default".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "globe")
                                .foregroundColor(.naarsPrimary)
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
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                    
                    Button(action: {
                        viewModel.triggerTestCrash()
                    }) {
                        Label {
                            Text("Test Crash")
                                .foregroundColor(.naarsError)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.naarsError)
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
                                .foregroundColor(.naarsWarning)
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
                                .foregroundColor(.naarsError)
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
                                .foregroundColor(.naarsPrimary)
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
                            .accessibilityLabel("settings_supreme_leader_accessibility".localized)
                        
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
                            .font(.naarsCaption2)
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
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                    
                    // Privacy Policy Link
                    Link(destination: URL(string: Constants.URLs.privacyPolicy) ?? URL(string: "about:blank") ?? URL(fileURLWithPath: "/")) {
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
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                    
                    // Terms of Service Link
                    Link(destination: URL(string: Constants.URLs.termsOfService) ?? URL(string: "about:blank") ?? URL(fileURLWithPath: "/")) {
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
                                .foregroundColor(.naarsPrimary)
                        }
                    }

                    // Contact Support
                    Button {
                        openContactSupport()
                    } label: {
                        Label {
                            HStack {
                                Text("settings_contact_support".localized)
                                    .font(.naarsBody)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "envelope")
                                .foregroundColor(.naarsPrimary)
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
                        onCompletion: { credential, rawNonce in
                            Task {
                                await viewModel.linkAppleAccount(credential: credential, rawNonce: rawNonce)
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

    private func openContactSupport() {
        let subject = "settings_contact_support_subject".localized
        let appVersion = Bundle.main.appVersion
        let buildNumber = Bundle.main.buildNumber
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let body = "\n\n---\n\("settings_contact_support_device_info".localized)\n\("app_name".localized) \(appVersion) (\(buildNumber))\niOS \(systemVersion) — \(deviceModel)"

        let email = "naarscars@gmail.com"
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:\(email)?subject=\(subjectEncoded)&body=\(bodyEncoded)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - View Model

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var biometricsEnabled = false
    @Published var requireBiometricsOnLaunch = false
    /// Mirrors the iOS notification permission for this app. It is never set by a control in
    /// the app: only iOS can turn notifications on or off once the first prompt was answered.
    @Published var pushNotificationsEnabled = false
    /// True when the permission was refused, so the only route left is the Settings app
    @Published var pushPermissionDenied = false
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
    
    /// The value the server last confirmed for each notification switch. The switches write
    /// through onChange, which also fires when a value is loaded or reverted; comparing with
    /// this keeps those from re-sending a save (a failed save used to flip the switch back,
    /// which re-fired the save, indefinitely).
    private var confirmedNotificationPreferences: [NotificationPreferenceType: Bool] = [:]

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
        await refreshPushAuthorizationStatus()

        // Check if Apple ID is linked
        isAppleLinked = await AuthService.shared.checkAppleIdentityLinked()
        
        // Load theme preference
        selectedTheme = themeManager.currentTheme
        
        // Load crash reporting preference
        crashReportingEnabled = crashReportingService.isEnabled
        
        // Load notification preferences from profile
        if let userId = AuthService.shared.currentUserId,
           let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
            confirmedNotificationPreferences = [
                .rideUpdates: profile.notifyRideUpdates,
                .messages: profile.notifyMessages,
                .qaActivity: profile.notifyQaActivity,
                .reviewReminders: profile.notifyReviewReminders,
                .townHall: profile.notifyTownHall
            ]
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
        // The view's onChange also fires when loadSettings() assigns the stored value and when
        // a cancelled prompt sets the switch back. Acting on those showed a Face ID prompt every
        // time Settings opened, and cancelling it turned app lock off. Only act on a real change.
        guard enabled != biometricPreferences.isBiometricsEnabled else { return }
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
    
    /// Re-read the iOS notification permission. Called when Settings loads and each time the
    /// app becomes active again, so the row is right after a trip to the Settings app.
    func refreshPushAuthorizationStatus() async {
        let authStatus = await pushNotificationService.checkAuthorizationStatus()
        pushNotificationsEnabled = authStatus == .authorized || authStatus == .provisional
        pushPermissionDenied = authStatus == .denied
    }

    /// The button on the Push Notifications row. The app can ask iOS for permission once;
    /// after that (allowed or refused) the only place to change it is the Settings app, so
    /// the button goes there instead of pretending to switch notifications off or on.
    func handlePushPermissionAction() async {
        if pushNotificationsEnabled || pushPermissionDenied {
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
            _ = await UIApplication.shared.open(url)
            return
        }

        // Never asked: show the system prompt. Device token registration is handled by
        // AppDelegate when didRegisterForRemoteNotificationsWithDeviceToken is called.
        _ = await pushNotificationService.requestPermission()
        await refreshPushAuthorizationStatus()
    }
    
    func updateNotificationPreference(_ type: NotificationPreferenceType, enabled: Bool) async {
        // Nothing to save when the switch only moved to the value the server already has
        // (settings loading, or a failed save being reverted).
        if let confirmed = confirmedNotificationPreferences[type], confirmed == enabled { return }
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
            
            confirmedNotificationPreferences[type] = enabled

            // Refresh profile cache
            await CacheManager.shared.invalidateProfile(id: userId)
        } catch {
            errorMessage = String(format: "settings_notification_update_failed".localized, error.localizedDescription)
            showError = true
            confirmedNotificationPreferences[type] = !enabled
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
    
    func linkAppleAccount(credential: ASAuthorizationAppleIDCredential, rawNonce: String? = nil) async {
        do {
            try await AuthService.shared.linkAppleAccount(credential: credential, rawNonce: rawNonce)
            isAppleLinked = true
            startAppleLinking = false
            await loadSettings()
        } catch {
            errorMessage = String(format: "settings_link_apple_failed".localized, error.localizedDescription)
            showError = true
        }
    }

    func unlinkAppleAccount() async {
        do {
            try await AuthService.shared.unlinkAppleAccount()
            isAppleLinked = false
            await loadSettings()
        } catch {
            errorMessage = error.localizedDescription
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
    @StateObject private var viewModel = BlockedUsersViewModel()
    @State private var showUnblockConfirmation = false
    @State private var userToUnblock: BlockedUser?
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("common_loading".localized)
            } else if let loadError = viewModel.error, viewModel.blockedUsers.isEmpty {
                // A failed load is not "nobody is blocked".
                ErrorView(
                    error: loadError,
                    retryAction: {
                        Task { await viewModel.loadBlockedUsers() }
                    }
                )
            } else if viewModel.blockedUsers.isEmpty {
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
                    ForEach(viewModel.blockedUsers) { blockedUser in
                        HStack(spacing: 12) {
                            // Avatar
                            AvatarView(
                                imageUrl: blockedUser.blockedAvatarUrl,
                                name: blockedUser.blockedName,
                                size: 44,
                                userId: blockedUser.blockedId
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
            await viewModel.loadBlockedUsers()
        }
        .alert("settings_unblock_user".localized, isPresented: $showUnblockConfirmation) {
            Button("common_cancel".localized, role: .cancel) {
                userToUnblock = nil
            }
            Button("settings_unblock".localized) {
                if let user = userToUnblock {
                    Task {
                        await viewModel.unblockUser(user)
                    }
                }
                userToUnblock = nil
            }
        } message: {
            if let user = userToUnblock {
                Text(String(format: "settings_unblock_confirmation".localized, user.blockedName))
            }
        }
        .errorBanner(message: $viewModel.unblockErrorMessage)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}

#Preview("Blocked Users") {
    NavigationStack {
        BlockedUsersView()
    }
}
