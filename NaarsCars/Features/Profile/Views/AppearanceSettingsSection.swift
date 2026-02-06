//
//  AppearanceSettingsSection.swift
//  NaarsCars
//
//  Appearance/theme settings section extracted from SettingsView
//

import SwiftUI

/// Section for configuring the app's visual theme (light, dark, system)
struct AppearanceSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Picker(selection: $viewModel.selectedTheme) {
                ForEach(ThemeMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text("settings_appearance".localized)
                            .font(.naarsBody)
                        Text(viewModel.selectedTheme.displayName)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: viewModel.selectedTheme.iconName)
                        .foregroundColor(.accentColor)
                }
            }
            .onChange(of: viewModel.selectedTheme) { _, newValue in
                HapticManager.selectionChanged()
                viewModel.updateTheme(newValue)
            }
        } header: {
            Text("settings_display".localized)
        } footer: {
            Text("settings_appearance_footer".localized)
                .font(.naarsCaption)
        }
    }
}
