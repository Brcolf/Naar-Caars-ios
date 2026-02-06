//
//  MessagingSettingsSection.swift
//  NaarsCars
//
//  Messaging preferences section extracted from SettingsView
//

import SwiftUI

/// Section for configuring messaging preferences (read receipts, typing indicators, etc.)
struct MessagingSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            // Send Read Receipts
            Toggle(isOn: $viewModel.sendReadReceipts) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_send_read_receipts".localized)
                            .font(.naarsBody)
                        Text("settings_read_receipts_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.message.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.sendReadReceipts) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateMessagingPreference(.sendReadReceipts, enabled: newValue)
            }

            // Show Typing Indicators
            Toggle(isOn: $viewModel.showTypingIndicators) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_typing_indicators".localized)
                            .font(.naarsBody)
                        Text("settings_typing_indicators_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "ellipsis.message.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.showTypingIndicators) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateMessagingPreference(.showTypingIndicators, enabled: newValue)
            }

            // Link Previews
            Toggle(isOn: $viewModel.showLinkPreviews) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_link_previews".localized)
                            .font(.naarsBody)
                        Text("settings_link_previews_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.showLinkPreviews) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateMessagingPreference(.showLinkPreviews, enabled: newValue)
            }

            // Auto-download Media
            Toggle(isOn: $viewModel.autoDownloadMedia) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_auto_download_media".localized)
                            .font(.naarsBody)
                        Text("settings_auto_download_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.autoDownloadMedia) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateMessagingPreference(.autoDownloadMedia, enabled: newValue)
            }

            // Blocked Users
            NavigationLink(destination: BlockedUsersView()) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_blocked_users".localized)
                            .font(.naarsBody)
                        Text("settings_manage_blocked_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .foregroundColor(.accentColor)
                }
            }
        } header: {
            Text("settings_messaging".localized)
        } footer: {
            Text("settings_messaging_footer".localized)
                .font(.naarsCaption)
        }
    }
}
