//
//  PrivacySettingsSection.swift
//  NaarsCars
//
//  Privacy settings section extracted from SettingsView
//

import SwiftUI

/// Section for privacy-related preferences (crash reporting, etc.)
struct PrivacySettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.crashReportingEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_share_crash_reports".localized)
                            .font(.naarsBody)
                        Text("settings_crash_reports_description".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "ant.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.crashReportingEnabled) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateCrashReporting(newValue)
            }
        } header: {
            Text("settings_privacy".localized)
        } footer: {
            Text("settings_privacy_footer".localized)
                .font(.naarsCaption)
        }
    }
}
