//
//  AccountSettingsSection.swift
//  NaarsCars
//
//  Account management section extracted from SettingsView
//

import SwiftUI

/// Section for account linking and management (Apple ID linking, etc.)
struct AccountSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showUnlinkConfirmation = false

    var body: some View {
        Section {
            if !viewModel.isAppleLinked {
                Button(action: {
                    viewModel.showLinkAppleAlert = true
                }) {
                    Label {
                        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                            Text("settings_link_apple_id".localized)
                                .font(.naarsBody)
                            Text("settings_apple_signin_description".localized)
                                .font(.naarsCaption)
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
                    Text("settings_apple_id_linked".localized)
                        .font(.naarsBody)
                    Spacer()
                    Button("settings_unlink".localized, role: .destructive) {
                        showUnlinkConfirmation = true
                    }
                    .font(.naarsCaption)
                }
                .confirmationDialog(
                    "settings_unlink_apple_id_title".localized,
                    isPresented: $showUnlinkConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("settings_unlink_apple_id_confirm".localized, role: .destructive) {
                        Task {
                            await viewModel.unlinkAppleAccount()
                        }
                    }
                    Button("common_cancel".localized, role: .cancel) {}
                } message: {
                    Text("settings_unlink_apple_id_message".localized)
                }
            }
        } header: {
            Text("settings_account_linking".localized)
        } footer: {
            if !viewModel.isAppleLinked {
                Text("settings_link_apple_id_description".localized)
                    .font(.naarsCaption)
            }
        }
    }
}
