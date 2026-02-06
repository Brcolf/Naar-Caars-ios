//
//  ClaimViewModel.swift
//  NaarsCars
//
//  ViewModel for claim-related operations
//

import Foundation
internal import Combine
import UserNotifications

/// ViewModel for claim-related operations
@MainActor
final class ClaimViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showPhoneRequired: Bool = false
    @Published var showPushPermissionPrompt: Bool = false
    
    // MARK: - Private Properties
    
    private let claimService = ClaimService.shared
    private let authService = AuthService.shared
    private let profileService = ProfileService.shared
    
    // MARK: - Public Methods
    
    /// Check if user can claim (has phone number)
    /// - Returns: True if user has phone number, false otherwise
    func checkCanClaim() async -> Bool {
        guard let userId = authService.currentUserId else {
            return false
        }
        
        do {
            let profile = try await profileService.fetchProfile(userId: userId)
            return profile.phoneNumber != nil && !profile.phoneNumber!.isEmpty
        } catch {
            return false
        }
    }
    
    /// Claim a request
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    /// - Throws: AppError if claim fails
    func claim(requestType: String, requestId: UUID) async throws {
        guard let claimerId = authService.currentUserId else {
            throw AppError.notAuthenticated
        }
        
        // Check for phone number first
        let canClaim = await checkCanClaim()
        guard canClaim else {
            showPhoneRequired = true
            throw AppError.invalidInput("Phone number is required to claim requests")
        }
        
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        HapticManager.mediumImpact()
        
        do {
            // Log action for crash context
            CrashReportingService.shared.logAction("claim_request", parameters: [
                "request_type": requestType,
                "request_id": requestId.uuidString
            ])
            
            try await claimService.claimRequest(
                requestType: requestType,
                requestId: requestId,
                claimerId: claimerId
            )
            
            HapticManager.success()

            // Request push notification permission after first successful claim
            await requestPushPermissionIfNeeded()
        } catch {
            // Record non-fatal error
            CrashReportingService.shared.recordClaimingError(
                error,
                operation: "claim",
                requestType: requestType,
                requestId: requestId
            )
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Unclaim a request
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    /// - Throws: AppError if unclaim fails
    func unclaim(requestType: String, requestId: UUID) async throws {
        guard let claimerId = authService.currentUserId else {
            throw AppError.notAuthenticated
        }
        
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            CrashReportingService.shared.logAction("unclaim_request", parameters: [
                "request_type": requestType,
                "request_id": requestId.uuidString
            ])
            
            try await claimService.unclaimRequest(
                requestType: requestType,
                requestId: requestId,
                claimerId: claimerId
            )
            
            HapticManager.mediumImpact()
        } catch {
            CrashReportingService.shared.recordClaimingError(
                error,
                operation: "unclaim",
                requestType: requestType,
                requestId: requestId
            )
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Complete a request (poster only)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    /// - Throws: AppError if complete fails
    func complete(requestType: String, requestId: UUID) async throws {
        guard let posterId = authService.currentUserId else {
            throw AppError.notAuthenticated
        }
        
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            CrashReportingService.shared.logAction("complete_request", parameters: [
                "request_type": requestType,
                "request_id": requestId.uuidString
            ])
            
            try await claimService.completeRequest(
                requestType: requestType,
                requestId: requestId,
                posterId: posterId
            )
            
            HapticManager.success()
        } catch {
            CrashReportingService.shared.recordClaimingError(
                error,
                operation: "complete",
                requestType: requestType,
                requestId: requestId
            )
            self.error = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Push Notification Permission
    
    /// Request push notification permission after first claim
    /// Only shows prompt once per user
    private func requestPushPermissionIfNeeded() async {
        // Check if we've already requested permission
        let hasRequestedPermission = UserDefaults.standard.bool(forKey: "hasRequestedPushPermission")
        
        guard !hasRequestedPermission else {
            return
        }
        
        // Check current authorization status
        let status = await PushNotificationService.shared.checkAuthorizationStatus()
        
        // Only show prompt if permission hasn't been determined
        if status == .notDetermined {
            // Mark that we've requested permission
            UserDefaults.standard.set(true, forKey: "hasRequestedPushPermission")
            
            // Show custom prompt explaining benefits
            showPushPermissionPrompt = true
        }
    }
}



