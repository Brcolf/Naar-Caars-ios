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
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                if let validationError = viewModel.validationError {
                    Section {
                        Text(validationError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .overlay {
                if viewModel.isSaving || viewModel.isUploadingAvatar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                        if viewModel.isUploadingAvatar {
                            Text("Uploading avatar...")
                                .padding(.top)
                        } else {
                            Text("Saving...")
                                .padding(.top)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
            }
            .alert("Phone Number Visibility", isPresented: $showPhoneDisclosure) {
                Button("Cancel", role: .cancel) {}
                Button("Yes, Save Number") {
                    Task {
                        let success = await viewModel.confirmAndSave()
                        if success {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Your phone number will be visible to other Naar's Cars members to coordinate rides and favors. Continue?")
            }
            .alert("Photo Access Required", isPresented: $showPhotoPermissionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
            } message: {
                Text("To change your profile photo, please enable photo access in Settings.")
            }
        }
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
                    imageUrl: nil,
                    name: viewModel.name,
                    size: 120
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
                Text("Change Photo")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
    
    // MARK: - Name Field
    
    private func nameField() -> some View {
        TextField("Name", text: $viewModel.name)
            .textInputAutocapitalization(.words)
    }
    
    // MARK: - Phone Field
    
    private func phoneField() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Phone Number", text: $viewModel.phoneNumber)
                .keyboardType(.phonePad)
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
                    .font(.caption)
                Text("Your phone number will be visible to community members for ride coordination.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Car Field
    
    private func carField() -> some View {
        TextField("Car Description", text: $viewModel.car, axis: .vertical)
            .lineLimit(3...6)
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





