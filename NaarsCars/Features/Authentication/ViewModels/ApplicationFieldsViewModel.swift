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

    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.profileService = profileService
        self.authService = authService
    }

    /// Sanitize, validate and submit. Returns true on success (caller transitions launch state).
    /// On success `isSubmitting` stays true because the screen is replaced.
    func submitApplication(heardAbout: String, joinReason: String) async -> Bool {
        guard let userId = authService.currentUserId else {
            errorMessage = "application_error_not_signed_in".localized
            return false
        }

        let trimmedHeardAbout = Validators.sanitizeUserInput(heardAbout, maxLength: 500)
        let trimmedJoinReason = Validators.sanitizeUserInput(joinReason, maxLength: 500)

        guard !trimmedHeardAbout.isEmpty, !trimmedJoinReason.isEmpty else {
            errorMessage = "application_error_fields_required".localized
            return false
        }

        isSubmitting = true
        errorMessage = nil

        do {
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
