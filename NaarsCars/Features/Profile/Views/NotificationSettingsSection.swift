//
//  NotificationSettingsSection.swift
//  NaarsCars
//
//  Notification preferences section extracted from SettingsView
//

import SwiftUI

/// Section for configuring push notification preferences
struct NotificationSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    /// What iOS currently allows, in words
    private var pushStatusText: String {
        if viewModel.pushNotificationsEnabled {
            return "settings_push_status_on".localized
        }
        return viewModel.pushPermissionDenied
            ? "settings_push_status_denied".localized
            : "settings_push_status_off".localized
    }

    /// Asking is only possible before the first answer; afterwards the Settings app decides.
    private var pushActionTitle: String {
        if viewModel.pushNotificationsEnabled {
            return "settings_push_manage_in_settings".localized
        }
        return viewModel.pushPermissionDenied
            ? "edit_profile_open_settings".localized
            : "settings_push_turn_on".localized
    }

    var body: some View {
        Section {
            // Push notification status. This used to be a switch, but an app cannot turn its
            // own notification permission off: the switch changed nothing and was back on the
            // next time Settings opened. The row now shows what iOS reports and the button
            // goes to the place that can change it.
            Label {
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text("settings_push_notifications".localized)
                        .font(.naarsBody)
                    Text(pushStatusText)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: viewModel.pushNotificationsEnabled ? "bell.badge" : "bell.slash")
                    .foregroundColor(.naarsPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.push.status")
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Back from the Settings app: show what was chosen there.
                Task {
                    await viewModel.refreshPushAuthorizationStatus()
                }
            }

            Button {
                HapticManager.selectionChanged()
                Task {
                    await viewModel.handlePushPermissionAction()
                }
            } label: {
                Text(pushActionTitle)
                    .font(.naarsBody)
            }
            .accessibilityIdentifier("settings.push.action")

            if viewModel.pushNotificationsEnabled {
                // Notification Type Preferences
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings_notification_types".localized)
                        .font(.naarsHeadline)
                        .padding(.top, 8)

                    Toggle(isOn: $viewModel.notifyRideUpdates) {
                        Text("settings_ride_updates".localized)
                            .font(.naarsBody)
                    }
                    .onChange(of: viewModel.notifyRideUpdates) { _, newValue in
                        HapticManager.selectionChanged()
                        Task {
                            await viewModel.updateNotificationPreference(.rideUpdates, enabled: newValue)
                        }
                    }

                    Toggle(isOn: $viewModel.notifyMessages) {
                        Text("settings_messages".localized)
                            .font(.naarsBody)
                    }
                    .onChange(of: viewModel.notifyMessages) { _, newValue in
                        HapticManager.selectionChanged()
                        Task {
                            await viewModel.updateNotificationPreference(.messages, enabled: newValue)
                        }
                    }

                    Toggle(isOn: $viewModel.notifyAnnouncements) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings_announcements".localized)
                                .font(.naarsBody)
                            Text("settings_always_enabled".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(true)

                    Toggle(isOn: $viewModel.notifyNewRequests) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings_new_requests".localized)
                                .font(.naarsBody)
                            Text("settings_always_enabled".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(true)

                    Toggle(isOn: $viewModel.notifyQaActivity) {
                        Text("settings_qa_activity".localized)
                            .font(.naarsBody)
                    }
                    .onChange(of: viewModel.notifyQaActivity) { _, newValue in
                        HapticManager.selectionChanged()
                        Task {
                            await viewModel.updateNotificationPreference(.qaActivity, enabled: newValue)
                        }
                    }

                    Toggle(isOn: $viewModel.notifyReviewReminders) {
                        Text("settings_review_reminders".localized)
                            .font(.naarsBody)
                    }
                    .onChange(of: viewModel.notifyReviewReminders) { _, newValue in
                        HapticManager.selectionChanged()
                        Task {
                            await viewModel.updateNotificationPreference(.reviewReminders, enabled: newValue)
                        }
                    }

                    Toggle(isOn: $viewModel.notifyTownHall) {
                        Text("settings_town_hall".localized)
                            .font(.naarsBody)
                    }
                    .onChange(of: viewModel.notifyTownHall) { _, newValue in
                        HapticManager.selectionChanged()
                        Task {
                            await viewModel.updateNotificationPreference(.townHall, enabled: newValue)
                        }
                    }
                }
            }
        } header: {
            Text("settings_notifications".localized)
        } footer: {
            if viewModel.pushNotificationsEnabled {
                Text("settings_notifications_required_footer".localized)
                    .font(.naarsCaption)
                Text("settings_notifications_control_footer".localized)
                    .font(.naarsCaption)
            }
        }
    }
}
