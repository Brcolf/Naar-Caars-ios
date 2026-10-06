//
//  MessagingSettingsSection.swift
//  NaarsCars
//
//  Messaging preferences section extracted from SettingsView
//

import SwiftUI

/// Section for configuring messaging preferences (link previews, blocked users)
struct MessagingSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            // Read receipts, typing indicators and auto-download are not offered here: their
            // switches saved a preference that nothing read, so turning read receipts off still
            // sent them. Bring a row back only together with the code that honours it (read
            // receipts are already a real per-conversation setting in conversation details).

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
                        .foregroundColor(.naarsPrimary)
                }
            }
            .onChange(of: viewModel.showLinkPreviews) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateMessagingPreference(.showLinkPreviews, enabled: newValue)
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
                        .foregroundColor(.naarsPrimary)
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
