//
//  LanguageSettingsView.swift
//  NaarsCars
//
//  Language selection interface for app localization
//

import SwiftUI

/// View for selecting app language
struct LanguageSettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showRestartAlert = false
    @State private var pendingLanguage: String?
    
    var body: some View {
        Form {
            Section {
                ForEach(LocalizationManager.supportedLanguages) { language in
                    Button {
                        selectLanguage(language.code)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.localizedName)
                                    .foregroundColor(.primary)
                                    .font(.body)
                                if language.code != "system" && language.localizedName != language.name {
                                    Text(language.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if language.code == localizationManager.appLanguage {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.body)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } footer: {
                Text("language_restart_required".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("language_settings_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("language_restart_alert_title".localized, isPresented: $showRestartAlert) {
            Button("language_restart_now".localized) {
                if let language = pendingLanguage {
                    localizationManager.setLanguage(language)
                    // Force app restart by exiting
                    exit(0)
                }
            }
            Button("common_later".localized, role: .cancel) {
                if let language = pendingLanguage {
                    localizationManager.setLanguage(language)
                    dismiss()
                }
            }
        } message: {
            Text("language_restart_alert_message".localized)
        }
    }
    
    private func selectLanguage(_ code: String) {
        guard code != localizationManager.appLanguage else { return }
        pendingLanguage = code
        showRestartAlert = true
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
    }
}

