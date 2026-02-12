//
//  EditProfileViewModel.swift
//  NaarsCars
//
//  View model for editing user profile
//

import Foundation
import SwiftUI
internal import Combine
import PhotosUI

/// View model for editing profile
@MainActor
final class EditProfileViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var name: String = ""
    @Published var phoneNumber: String = ""
    @Published var car: String = ""
    @Published var avatarImage: UIImage?
    @Published var isSaving: Bool = false
    @Published var isUploadingAvatar: Bool = false
    @Published var error: AppError?
    @Published var validationError: String?
    
    // MARK: - Private Properties
    
    private let profileService: any ProfileServiceProtocol
    private let userId: UUID
    private let originalPhoneNumber: String?
    
    /// The existing avatar URL from the profile (used as fallback while no new photo is selected)
    let existingAvatarUrl: String?
    
    // Phone visibility disclosure tracking
    private let phoneDisclosureKey = "hasShownPhoneDisclosure"
    private var hasShownPhoneDisclosure: Bool {
        get {
            UserDefaults.standard.bool(forKey: phoneDisclosureKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: phoneDisclosureKey)
        }
    }
    
    // MARK: - Initialization
    
    init(
        profile: Profile,
        profileService: any ProfileServiceProtocol = ProfileService.shared
    ) {
        self.profileService = profileService
        self.userId = profile.id
        self.name = profile.name
        self.phoneNumber = profile.phoneNumber ?? ""
        self.originalPhoneNumber = profile.phoneNumber
        self.car = profile.car ?? ""
        self.existingAvatarUrl = profile.avatarUrl
        
        // Load avatar if URL exists
        if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
            Task {
                await loadAvatar(from: url)
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Validate and save profile changes
    /// Shows phone visibility disclosure if first time adding phone
    /// - Returns: true if save successful, false otherwise
    func validateAndSave() async -> Bool {
        // Clear previous errors
        error = nil
        validationError = nil
        
        // Validate name
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "profile_name_required".localized
            return false
        }
        
        // Validate phone if provided
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespaces)
        if !trimmedPhone.isEmpty {
            guard Validators.isValidPhoneNumber(trimmedPhone) else {
                validationError = "profile_invalid_phone".localized
                return false
            }
        }
        
        // Check if this is first time adding phone number
        let isAddingPhoneForFirstTime = originalPhoneNumber == nil && !trimmedPhone.isEmpty
        
        if isAddingPhoneForFirstTime && !hasShownPhoneDisclosure {
            // Return false to trigger disclosure alert in view
            // View will call confirmAndSave() after user confirms
            return false
        }
        
        return await performSave()
    }
    
    /// Confirm and save after phone disclosure
    /// Called after user confirms phone visibility disclosure
    func confirmAndSave() async -> Bool {
        hasShownPhoneDisclosure = true
        return await performSave()
    }
    
    /// Perform the actual save operation
    private func performSave() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        
        do {
            // Format phone number for storage
            var formattedPhone: String? = nil
            let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespaces)
            if !trimmedPhone.isEmpty {
                formattedPhone = Validators.formatPhoneForStorage(trimmedPhone)
            }
            
            // Upload avatar if selected
            var avatarUrl: String? = nil
            if let avatarImage = avatarImage {
                isUploadingAvatar = true
                defer { isUploadingAvatar = false }
                
                guard let imageData = avatarImage.jpegData(compressionQuality: 1.0) else {
                    error = AppError.processingError("profile_image_process_failed".localized)
                    return false
                }
                
                avatarUrl = try await profileService.uploadAvatar(
                    imageData: imageData,
                    userId: userId
                )
            }
            
            // Update profile
            try await profileService.updateProfile(
                userId: userId,
                name: name.trimmingCharacters(in: .whitespaces),
                phoneNumber: formattedPhone,
                car: car.trimmingCharacters(in: .whitespaces).isEmpty ? nil : car.trimmingCharacters(in: .whitespaces),
                avatarUrl: avatarUrl,
                shouldUpdateAvatar: avatarUrl != nil
            )
            
            // Re-fetch profile to ensure local state is perfectly in sync with server
            if let updatedProfile = try? await profileService.fetchProfile(userId: userId) {
                // This ensures the next time the view loads, it has the latest data
                await CacheManager.shared.cacheProfile(updatedProfile)
            }
            
            return true
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
            return false
        }
    }
    
    /// Handle PhotosPicker selection
    /// - Parameter item: Selected PhotosPickerItem
    func handleAvatarSelection(_ item: PhotosPickerItem?) async {
        guard let item = item else {
            avatarImage = nil
            return
        }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                error = AppError.invalidInput("profile_image_load_failed".localized)
                return
            }
            
            guard let uiImage = UIImage(data: data) else {
                error = AppError.invalidInput("profile_invalid_image_format".localized)
                return
            }
            
            // Compress image using avatar preset
            guard let compressedData = await ImageCompressor.compressAsync(uiImage, preset: .avatar) else {
                error = AppError.processingError("profile_image_too_large".localized)
                return
            }
            
            guard let compressedImage = UIImage(data: compressedData) else {
                error = AppError.processingError("profile_image_compress_failed".localized)
                return
            }
            
            avatarImage = compressedImage
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAvatar(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            avatarImage = UIImage(data: data)
        } catch {
            // Silently fail - avatar will just not show
        }
    }
}

