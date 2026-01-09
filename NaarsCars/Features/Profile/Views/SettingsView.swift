//
//  SettingsView.swift
//  NaarsCars
//
//  Settings view with biometric authentication and notification preferences
//

import SwiftUI
import UserNotifications
import AuthenticationServices

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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Use \(biometricService.biometricType.displayName)")
                                        .font(.body)
                                    Text("Quickly unlock the app")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: biometricService.biometricType.iconName)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .onChange(of: viewModel.biometricsEnabled) { _, newValue in
                            Task {
                                await viewModel.handleBiometricsToggle(newValue)
                            }
                        }
                        
                        if viewModel.biometricsEnabled {
                            Toggle(isOn: $viewModel.requireBiometricsOnLaunch) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Require on Launch")
                                        .font(.body)
                                    Text("Lock when returning to app")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onChange(of: viewModel.requireBiometricsOnLaunch) { _, newValue in
                                viewModel.updateRequireOnLaunch(newValue)
                            }
                        }
                    } header: {
                        Text("Biometric Authentication")
                    } footer: {
                        if viewModel.biometricsEnabled && viewModel.requireBiometricsOnLaunch {
                            Text("App will lock after 5 minutes in background")
                                .font(.caption)
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Biometric authentication is not available on this device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Biometric Authentication")
                    }
                }
                
                // Notification Settings Section
                Section {
                    // Push Notification Toggle
                    Toggle(isOn: $viewModel.pushNotificationsEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Push Notifications")
                                    .font(.body)
                                Text("Receive notifications on your device")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .onChange(of: viewModel.pushNotificationsEnabled) { _, newValue in
                        Task {
                            await viewModel.handlePushNotificationToggle(newValue)
                        }
                    }
                    
                    if viewModel.pushNotificationsEnabled {
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Notification Type Preferences
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notification Types")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            Toggle(isOn: $viewModel.notifyRideUpdates) {
                                Text("Ride Updates")
                                    .font(.body)
                            }
                            .onChange(of: viewModel.notifyRideUpdates) { _, newValue in
                                Task {
                                    await viewModel.updateNotificationPreference(.rideUpdates, enabled: newValue)
                                }
                            }
                            
                            Toggle(isOn: $viewModel.notifyMessages) {
                                Text("Messages")
                                    .font(.body)
                            }
                            .onChange(of: viewModel.notifyMessages) { _, newValue in
                                Task {
                                    await viewModel.updateNotificationPreference(.messages, enabled: newValue)
                                }
                            }
                            
                            Toggle(isOn: $viewModel.notifyAnnouncements) {
                                Text("Announcements")
                                    .font(.body)
                            }
                            .onChange(of: viewModel.notifyAnnouncements) { _, newValue in
                                Task {
                                    await viewModel.updateNotificationPreference(.announcements, enabled: newValue)
                                }
                            }
                            
                            Toggle(isOn: $viewModel.notifyNewRequests) {
                                Text("New Requests")
                                    .font(.body)
                            }
                            .onChange(of: viewModel.notifyNewRequests) { _, newValue in
                                Task {
                                    await viewModel.updateNotificationPreference(.newRequests, enabled: newValue)
                                }
                            }
                            
                            Toggle(isOn: $viewModel.notifyQaActivity) {
                                Text("Q&A Activity")
                                    .font(.body)
                            }
                            .onChange(of: viewModel.notifyQaActivity) { _, newValue in
                                Task {
                                    await viewModel.updateNotificationPreference(.qaActivity, enabled: newValue)
                                }
                            }
                            
                            Toggle(isOn: $viewModel.notifyReviewReminders) {
                                Text("Review Reminders")
                                    .font(.body)
                            }
                            .onChange(of: viewModel.notifyReviewReminders) { _, newValue in
                                Task {
                                    await viewModel.updateNotificationPreference(.reviewReminders, enabled: newValue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if viewModel.pushNotificationsEnabled {
                        Text("Control which types of notifications you receive")
                            .font(.caption)
                    }
                }
                
                // Account Linking Section
                Section {
                    if !viewModel.isAppleLinked {
                        Button(action: {
                            viewModel.showLinkAppleAlert = true
                        }) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Link Apple ID")
                                        .font(.body)
                                    Text("Sign in with Apple on this account")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "apple.logo")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Apple ID linked")
                                .font(.body)
                            Spacer()
                        }
                    }
                } header: {
                    Text("Account Linking")
                } footer: {
                    if !viewModel.isAppleLinked {
                        Text("Link your Apple ID to sign in with Face ID/Touch ID")
                            .font(.caption)
                    }
                }
                
                // Language Settings Section
                Section {
                    NavigationLink(destination: LanguageSettingsView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Language")
                                    .font(.body)
                                Text(LocalizationManager.shared.supportedLanguages.first(where: { $0.code == LocalizationManager.shared.appLanguage })?.localizedName ?? "System Default")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "globe")
                                .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    Text("Localization")
                } footer: {
                    Text("Change the app's display language")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadSettings()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .alert("Link Apple ID", isPresented: $viewModel.showLinkAppleAlert) {
                Button("Link") {
                    viewModel.startAppleLinking = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll be able to sign in with Apple Sign-In after linking your account.")
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
                    .navigationTitle("Link Apple ID")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Cancel") {
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
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var isAppleLinked = false
    @Published var showLinkAppleAlert = false
    @Published var startAppleLinking = false
    
    private let biometricService = BiometricService.shared
    private let biometricPreferences = BiometricPreferences.shared
    private let pushNotificationService = PushNotificationService.shared
    
    func loadSettings() async {
        // Load biometric preferences
        biometricsEnabled = biometricPreferences.isBiometricsEnabled
        requireBiometricsOnLaunch = biometricPreferences.requireBiometricsOnLaunch
        
        // Load push notification status
        let authStatus = await pushNotificationService.checkAuthorizationStatus()
        pushNotificationsEnabled = authStatus == .authorized
        
        // Check if Apple ID is linked
        isAppleLinked = UserDefaults.standard.string(forKey: "appleUserIdentifier") != nil
        
        // Load notification preferences from profile
        if let userId = AuthService.shared.currentUserId,
           let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
            notifyRideUpdates = profile.notifyRideUpdates
            notifyMessages = profile.notifyMessages
            notifyAnnouncements = profile.notifyAnnouncements
            notifyNewRequests = profile.notifyNewRequests
            notifyQaActivity = profile.notifyQaActivity
            notifyReviewReminders = profile.notifyReviewReminders
        }
    }
    
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
                errorMessage = "Push notification permission was denied. You can enable it in Settings."
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
            errorMessage = "User not logged in"
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
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyAnnouncements: enabled
                )
                notifyAnnouncements = enabled
            case .newRequests:
                try await ProfileService.shared.updateNotificationPreferences(
                    userId: userId,
                    notifyNewRequests: enabled
                )
                notifyNewRequests = enabled
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
            }
            
            // Refresh profile cache
            await CacheManager.shared.invalidateProfile(id: userId)
        } catch {
            errorMessage = "Failed to update notification preference: \(error.localizedDescription)"
            showError = true
            // Revert toggle
            switch type {
            case .rideUpdates: notifyRideUpdates = !enabled
            case .messages: notifyMessages = !enabled
            case .announcements: notifyAnnouncements = !enabled
            case .newRequests: notifyNewRequests = !enabled
            case .qaActivity: notifyQaActivity = !enabled
            case .reviewReminders: notifyReviewReminders = !enabled
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
            errorMessage = "Failed to link Apple ID: \(error.localizedDescription)"
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
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

