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

    var body: some View {
        Section {
            // Push Notification Toggle
            Toggle(isOn: $viewModel.pushNotificationsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_push_notifications".localized)
                            .font(.naarsBody)
                        Text("settings_push_notifications_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.pushNotificationsEnabled) { _, newValue in
                HapticManager.selectionChanged()
                Task {
                    await viewModel.handlePushNotificationToggle(newValue)
                }
            }

            if viewModel.pushNotificationsEnabled {
                Divider()
                    .padding(.vertical, 4)

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
                        Text("settings_announcements".localized)
                            .font(.naarsBody)
                    }
                    .disabled(true)

                    Toggle(isOn: $viewModel.notifyNewRequests) {
                        Text("settings_new_requests".localized)
                            .font(.naarsBody)
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
