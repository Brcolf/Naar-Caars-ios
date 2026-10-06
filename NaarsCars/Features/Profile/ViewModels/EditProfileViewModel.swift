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
    /// A photo picked in this session, waiting to be uploaded on save. Nil means "keep the
    /// current photo": the existing one is shown from `existingAvatarUrl` and is not re-uploaded.
    @Published var avatarImage: UIImage?
    @Published var isSaving: Bool = false
    @Published var isUploadingAvatar: Bool = false
    @Published var error: AppError?
    @Published var validationError: String?
    
    // MARK: - Private Properties
    
    private let profileService: any ProfileServiceProtocol
    let userId: UUID
    private let originalName: String
    private let originalPhoneNumber: String?
    private let originalCar: String?

    /// True when something on the form differs from the saved profile, so leaving would lose it.
    /// The phone number is compared by digits: the field reformats what was loaded as it is typed in.
    var hasUnsavedChanges: Bool {
        if avatarImage != nil { return true }
        if name.trimmingCharacters(in: .whitespaces) != originalName.trimmingCharacters(in: .whitespaces) { return true }
        if car.trimmingCharacters(in: .whitespaces) != (originalCar ?? "").trimmingCharacters(in: .whitespaces) { return true }
        return phoneNumber.filter(\.isNumber) != (originalPhoneNumber ?? "").filter(\.isNumber)
    }

    /// The existing avatar URL from the profile (used as fallback while no new photo is selected)
    let existingAvatarUrl: String?
    
    // Phone visibility disclosure tracking
    // Remembered per account: with a per-device flag, a second account on the same phone was
    // never shown who can see its number.
    private var phoneDisclosureKey: String { "hasShownPhoneDisclosure_\(userId.uuidString)" }
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
        self.originalName = profile.name
        self.phoneNumber = profile.phoneNumber ?? ""
        self.originalPhoneNumber = profile.phoneNumber
        self.car = profile.car ?? ""
        self.originalCar = profile.car
        self.existingAvatarUrl = profile.avatarUrl

        // The current photo is not downloaded into `avatarImage`. It used to be, and every
        // save then re-compressed and re-uploaded it (so it degraded with each edit, and a
        // storage error blocked a name or phone change); a slow download could also replace
        // a photo the member had just picked. The view shows the current photo from its URL.
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
            // Format phone number for storage.
            // nil leaves the saved value alone and an empty string clears it (see
            // ProfileService.updateProfile). Emptying a field that had a value used to send
            // nil, so the old value stayed while the success checkmark played.
            var formattedPhone: String? = nil
            let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespaces)
            if !trimmedPhone.isEmpty {
                formattedPhone = Validators.formatPhoneForStorage(trimmedPhone)
            } else if !(originalPhoneNumber ?? "").isEmpty {
                formattedPhone = ""
            }

            let trimmedCar = car.trimmingCharacters(in: .whitespaces)
            var carValue: String? = trimmedCar.isEmpty ? nil : trimmedCar
            if trimmedCar.isEmpty, !(originalCar ?? "").isEmpty {
                carValue = ""
            }
            
            // Upload the avatar only when a new photo was picked in this session
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
                car: carValue,
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
}

