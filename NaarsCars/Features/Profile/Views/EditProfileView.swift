//
//  EditProfileView.swift
//  NaarsCars
//
//  View for editing user profile with phone visibility disclosure
//

import SwiftUI
import PhotosUI

/// View for editing user profile
struct EditProfileView: View {
    @StateObject private var viewModel: EditProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPhoneDisclosure = false
    @State private var showPhotoPermissionAlert = false
    @State private var showSuccess = false
    @State private var showDiscardConfirmation = false
    /// Set once a save has gone through, so the sheet may close while the checkmark plays
    @State private var didSave = false

    init(profile: Profile) {
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(profile: profile))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Avatar Section
                Section {
                    avatarSection()
                }
                
                // Profile Information Section
                Section {
                    nameField()
                    phoneField()
                    carField()
                }
                
                // Error Display
                if let error = viewModel.error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
                
                if let validationError = viewModel.validationError {
                    Section {
                        Text(validationError)
                            .foregroundColor(.naarsError)
                            .font(.naarsCaption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("edit_profile_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_cancel".localized) {
                        // Ask before throwing away edits; with nothing changed, just close.
                        if viewModel.hasUnsavedChanges && !didSave {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isSaving)
                    .accessibilityIdentifier("profile.edit.cancel")
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("edit_profile_save".localized) {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(viewModel.isSaving)
                    .accessibilityIdentifier("profile.edit.save")
                }
            }
            .overlay {
                if viewModel.isSaving || viewModel.isUploadingAvatar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                        if viewModel.isUploadingAvatar {
                            Text("edit_profile_uploading_avatar".localized)
                                .padding(.top)
                        } else {
                            Text("edit_profile_saving".localized)
                                .padding(.top)
                        }
                    }
                    .padding()
                    .background(Color.naarsBackgroundSecondary)
                    .cornerRadius(Constants.Radius.card)
                }
            }
            .alert("edit_profile_phone_visibility".localized, isPresented: $showPhoneDisclosure) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("edit_profile_save_number".localized) {
                    Task {
                        let success = await viewModel.confirmAndSave()
                        if success {
                            didSave = true
                            showSuccess = true
                            HapticManager.success()
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("profile_phone_privacy_notice".localized)
            }
            .confirmationDialog(
                "common_discard_changes_title".localized,
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("common_discard".localized, role: .destructive) {
                    dismiss()
                }
                Button("common_keep_editing".localized, role: .cancel) {}
            } message: {
                Text("edit_profile_discard_message".localized)
            }
            .alert("edit_profile_photo_access_required".localized, isPresented: $showPhotoPermissionAlert) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("edit_profile_open_settings".localized) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        Task { @MainActor in
                            await UIApplication.shared.open(settingsUrl)
                        }
                    }
                }
            } message: {
                Text("edit_profile_photo_access_message".localized)
            }
        }
        // A stray downward swipe must not discard edits or abandon a save in flight; Cancel
        // asks first. An untouched form can still be swiped away.
        .interactiveDismissDisabled((viewModel.hasUnsavedChanges && !didSave) || viewModel.isSaving)
        .successCheckmark(isShowing: $showSuccess)
    }
    
    // MARK: - Avatar Section
    
    private func avatarSection() -> some View {
        VStack(spacing: 16) {
            if let avatarImage = viewModel.avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else {
                AvatarView(
                    imageUrl: viewModel.existingAvatarUrl,
                    name: viewModel.name,
                    size: 120,
                    userId: viewModel.userId
                )
            }
            
            PhotosPicker(
                selection: Binding(
                    get: { nil },
                    set: { item in
                        Task {
                            await viewModel.handleAvatarSelection(item)
                        }
                    }
                ),
                matching: .images
            ) {
                Text("edit_profile_change_photo".localized)
                    .font(.naarsSubheadline)
            }
            .accessibilityIdentifier("profile.edit.changePhoto")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
    
    // MARK: - Name Field
    
    private func nameField() -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            fieldLabel("edit_profile_name".localized)
            TextField("edit_profile_name".localized, text: $viewModel.name)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .accessibilityIdentifier("profile.edit.name")
        }
    }
    
    // MARK: - Phone Field
    
    private func phoneField() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("edit_profile_phone_number".localized)
            TextField("edit_profile_phone_number".localized, text: $viewModel.phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .accessibilityIdentifier("profile.edit.phone")
                .onChange(of: viewModel.phoneNumber) { oldValue, newValue in
                    // Real-time phone formatting
                    let formatted = formatPhoneNumber(newValue)
                    if formatted != newValue {
                        viewModel.phoneNumber = formatted
                    }
                }
            
            // Info text about phone visibility
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
                // The same sentence as the save alert and the "phone required" sheet. The old
                // ones said other members could see the number; no screen shows it to them.
                Text("profile_phone_privacy_notice".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Car Field
    
    private func carField() -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            fieldLabel("edit_profile_car_description".localized)
            TextField("edit_profile_car_description".localized, text: $viewModel.car, axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("profile.edit.car")
        }
    }

    /// Caption shown above a field. A placeholder disappears once the field has a value, which
    /// left three unlabeled lines of text.
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.naarsCaption)
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
    }
    
    // MARK: - Helper Methods
    
    private func formatPhoneNumber(_ phone: String) -> String {
        // Remove all non-digit characters
        let digitsOnly = phone.filter { $0.isNumber }
        
        // Format as (XXX) XXX-XXXX for US numbers
        if digitsOnly.count <= 10 {
            var formatted = ""
            for (index, char) in digitsOnly.enumerated() {
                if index == 0 {
                    formatted += "("
                } else if index == 3 {
                    formatted += ") "
                } else if index == 6 {
                    formatted += "-"
                }
                formatted.append(char)
            }
            return formatted
        }
        
        return phone
    }
    
    private func saveProfile() async {
        let success = await viewModel.validateAndSave()
        
        if !success {
            // Check if we need to show phone disclosure
            if viewModel.validationError == nil && viewModel.error == nil {
                // This means phone disclosure is needed
                showPhoneDisclosure = true
            }
        } else {
            didSave = true
            showSuccess = true
            HapticManager.success()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        }
    }
}

#Preview {
    EditProfileView(profile: Profile(
        id: UUID(),
        name: "John Doe",
        email: "john@example.com",
        car: "Tesla Model 3",
        phoneNumber: "+15551234567",
        avatarUrl: nil
    ))
}





