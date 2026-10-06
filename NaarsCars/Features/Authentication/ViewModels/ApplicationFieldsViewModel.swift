//
//  ApplicationFieldsViewModel.swift
//  NaarsCars
//
//  View model for the post-auth application step
//

import Foundation
import os
internal import Combine

/// Validates and submits the application fields collected by ApplicationFieldsView
@MainActor
final class ApplicationFieldsViewModel: ObservableObject {
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    /// True when the stored profile has no usable name, so the form has to ask for one
    @Published var needsName = false
    @Published var nameError: String?

    /// Apple sends the person's name only on the first authorization. A repeat authorization
    /// (for example after starting on the Sign In screen) creates the profile with this
    /// placeholder, which admins and later neighbours would otherwise see.
    private static let applePlaceholderName = "Apple User"

    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.profileService = profileService
        self.authService = authService
    }

    /// Checks whether the profile still carries a blank or placeholder name. Failures leave
    /// the form as it is (no name field), which is the previous behaviour.
    func loadNameRequirement() async {
        guard let userId = await SignedInUser.resolveId(authService: authService) else { return }

        let storedName: String
        if let profile = authService.currentProfile, profile.id == userId {
            storedName = profile.name
        } else if let profile = try? await profileService.fetchProfile(userId: userId) {
            storedName = profile.name
        } else {
            return
        }

        let trimmedName = storedName.trimmingCharacters(in: .whitespacesAndNewlines)
        needsName = trimmedName.isEmpty || trimmedName == Self.applePlaceholderName
    }

    /// Same rules and messages as the name field on the sign-up form. Nil when the name is fine.
    private static func nameProblem(_ trimmedName: String) -> String? {
        if trimmedName.isEmpty || trimmedName == applePlaceholderName {
            return "signup_error_name_required".localized
        }
        if trimmedName.count < 2 {
            return "signup_error_name_too_short".localized
        }
        if trimmedName.count > 100 {
            return "signup_error_name_too_long".localized
        }
        if !Validators.isSafeUserInput(trimmedName) {
            return "signup_error_name_invalid_characters".localized
        }
        return nil
    }

    /// Sanitize, validate and submit. Returns true on success (caller transitions launch state).
    /// On success `isSubmitting` stays true because the screen is replaced.
    /// - Parameter name: Only read when `needsName` is true
    func submitApplication(name: String = "", heardAbout: String, joinReason: String) async -> Bool {
        guard let userId = await SignedInUser.resolveId(authService: authService) else {
            errorMessage = "application_error_not_signed_in".localized
            return false
        }

        var nameToSave: String?
        if needsName {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let problem = Self.nameProblem(trimmedName) {
                nameError = problem
                return false
            }
            nameToSave = Validators.sanitizeUserInput(trimmedName, maxLength: 100)
        }

        let trimmedHeardAbout = Validators.sanitizeUserInput(heardAbout, maxLength: 500)
        let trimmedJoinReason = Validators.sanitizeUserInput(joinReason, maxLength: 500)

        guard !trimmedHeardAbout.isEmpty, !trimmedJoinReason.isEmpty else {
            errorMessage = "application_error_fields_required".localized
            return false
        }

        isSubmitting = true
        errorMessage = nil
        nameError = nil

        do {
            if let nameToSave {
                try await profileService.updateProfile(
                    userId: userId,
                    name: nameToSave,
                    phoneNumber: nil,
                    car: nil,
                    avatarUrl: nil,
                    shouldUpdateAvatar: false
                )
            }
            try await profileService.submitApplication(
                userId: userId,
                heardAbout: trimmedHeardAbout,
                joinReason: trimmedJoinReason
            )
            return true
        } catch {
            AppLogger.auth.error("Failed to submit application: \(error.localizedDescription)")
            errorMessage = "application_error_submit_failed".localized
            isSubmitting = false
            return false
        }
    }
}
