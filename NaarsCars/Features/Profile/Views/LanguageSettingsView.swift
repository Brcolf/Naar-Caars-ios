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
                                    .font(.naarsBody)
                                if language.code != "system" && language.localizedName != language.name {
                                    Text(language.name)
                                        .font(.naarsCaption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if language.code == localizationManager.appLanguage {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.naarsBody)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } footer: {
                Text("language_restart_required".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("language_settings_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert("language_restart_alert_title".localized, isPresented: $showRestartAlert) {
            Button("common_ok".localized) {
                if let language = pendingLanguage {
                    localizationManager.setLanguage(language)
                    dismiss()
                }
            }
            Button("common_cancel".localized, role: .cancel) {
                pendingLanguage = nil
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

