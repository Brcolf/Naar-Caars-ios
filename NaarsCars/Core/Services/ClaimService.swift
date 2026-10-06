//
//  ClaimService.swift
//  NaarsCars
//
//  Service for claim-related operations
//

import Foundation
import Supabase

/// Service for claim-related operations
/// Handles claiming, unclaiming, and completing requests
final class ClaimService {
    
    // MARK: - Singleton
    
    static let shared = ClaimService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Claim Request
    
    /// Claim a request (ride or favor)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - claimerId: User ID of the claimer
    /// - Throws: AppError if claim fails
    func claimRequest(
        requestType: String,
        requestId: UUID,
        claimerId: UUID
    ) async throws {
        let operationStart = Date()
        // Check rate limit (10 seconds between claims)
        let rateLimitKey = "claim_request_\(claimerId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: Constants.RateLimits.claimRequest
        )
        
        guard canProceed else {
            await PerformanceMonitor.shared.record(
                operation: "claim.request.rejected",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "reason": "rate_limit"
                ]
            )
            throw AppError.rateLimitExceeded("Please wait before claiming another request")
        }
        
        // Verify user has phone number
        let profile = try await ProfileService.shared.fetchProfile(userId: claimerId)
        guard let phoneNumber = profile.phoneNumber, !phoneNumber.isEmpty else {
            await PerformanceMonitor.shared.record(
                operation: "claim.request.rejected",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "reason": "missing_phone"
                ]
            )
            throw AppError.invalidInput("Phone number is required to claim requests")
        }
        
        // Determine table name
        let tableName = requestType == "ride" ? "rides" : "favors"
        do {
            // Update request status to "confirmed" and set claimed_by
            let updates: [String: AnyCodable] = [
                "status": AnyCodable("confirmed"),
                "claimed_by": AnyCodable(claimerId.uuidString),
                "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
            ]
            
            let claimResponse = try await supabase
                .from(tableName)
                .update(updates)
                .eq("id", value: requestId.uuidString)
                .select("id")
                .execute()

            // The claim policy only matches an open, unclaimed request. When someone else got
            // there first the update touches no row and PostgREST still answers 200 with an
            // empty array. Without this check the second claimer saw the success checkmark and
            // the poster was notified of a claim that never happened.
            if let rows = try? JSONSerialization.jsonObject(with: claimResponse.data) as? [Any], rows.isEmpty {
                throw AppError.invalidInput("Someone else has already claimed this request.")
            }
            
            // The poster's in-app notification and push are both created by the database trigger
            // notify_ride_status_change / notify_favor_status_change (checked live 2026-10-06:
            // one "claimed" row per claim). The client used to follow the claim with a read of
            // the request, a read of the claimer's profile and its own insert into
            // `notifications`; RLS rejects a row for another user, so the insert never landed,
            // and a failure in either read made a claim that had succeeded look failed.

            // Completion reminders are server-scheduled via database triggers.
            await PerformanceMonitor.shared.record(
                operation: "claim.request.success",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString
                ],
                slowThreshold: Constants.Performance.claimOperationSlowThreshold
            )
        } catch {
            await PerformanceMonitor.shared.record(
                operation: "claim.request.failed",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "error": error.localizedDescription
                ]
            )
            throw error
        }
    }
    
    // MARK: - Unclaim Request
    
    /// Unclaim a request (reset to open)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - claimerId: User ID of the claimer (for verification)
    /// - Throws: AppError if unclaim fails
    func unclaimRequest(
        requestType: String,
        requestId: UUID,
        claimerId: UUID
    ) async throws {
        let operationStart = Date()
        // Check rate limit
        let rateLimitKey = "unclaim_request_\(claimerId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: Constants.RateLimits.claimRequest
        )
        
        guard canProceed else {
            await PerformanceMonitor.shared.record(
                operation: "claim.unclaim.rejected",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "reason": "rate_limit"
                ]
            )
            throw AppError.rateLimitExceeded("Please wait before unclaiming again")
        }
        
        // Determine table name
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        // Verify the claimer is the one who claimed it
        let response = try await supabase
            .from(tableName)
            .select("claimed_by")
            .eq("id", value: requestId.uuidString)
            .single()
            .execute()
        
        struct ClaimedBy: Codable {
            let claimedBy: UUID?
            
            enum CodingKeys: String, CodingKey {
                case claimedBy = "claimed_by"
            }
        }
        
        let claimedBy: ClaimedBy = try JSONDecoder().decode(ClaimedBy.self, from: response.data)
        
        guard claimedBy.claimedBy == claimerId else {
            await PerformanceMonitor.shared.record(
                operation: "claim.unclaim.rejected",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "reason": "not_current_claimer"
                ]
            )
            throw AppError.permissionDenied("You can only unclaim requests you claimed")
        }
        
        do {
            // Reset status to "open" and clear claimed_by
            let updates: [String: AnyCodable] = [
                "status": AnyCodable("open"),
                "claimed_by": AnyCodable(String?.none as Any),
                "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await supabase
                .from(tableName)
                .update(updates)
                .eq("id", value: requestId.uuidString)
                .execute()
            
            // The poster's "unclaimed" notification comes from the same database trigger as the
            // claim (see claimRequest); nothing more to send from here.
            await PerformanceMonitor.shared.record(
                operation: "claim.unclaim.success",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString
                ],
                slowThreshold: Constants.Performance.claimOperationSlowThreshold
            )
        } catch {
            await PerformanceMonitor.shared.record(
                operation: "claim.unclaim.failed",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "error": error.localizedDescription
                ]
            )
            throw error
        }
    }
    
    // MARK: - Complete Request
    
    /// Mark a confirmed request as completed through the `complete_request` RPC. The server
    /// accepts the poster or the claimer, closes the open completion reminders in the same
    /// transaction and sends the poster the review request. (This used to be a poster-only
    /// client guard in front of a direct UPDATE, so the claimer the completion reminder is
    /// addressed to could never complete a request from the app.)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - posterId: Kept for call-site compatibility; the server checks the caller's role.
    /// - Throws: AppError if the request is not confirmed or the caller is not a party to it
    func completeRequest(
        requestType: String,
        requestId: UUID,
        posterId: UUID
    ) async throws {
        let operationStart = Date()

        struct RPCResult: Decodable {
            let success: Bool
            let error: String?
        }

        do {
            let response = try await supabase
                .rpc("complete_request", params: [
                    "p_request_type": AnyCodable(requestType),
                    "p_request_id": AnyCodable(requestId.uuidString)
                ])
                .execute()
            let result = try JSONDecoder().decode(RPCResult.self, from: response.data)
            guard result.success else {
                await PerformanceMonitor.shared.record(
                    operation: "claim.complete.rejected",
                    duration: Date().timeIntervalSince(operationStart),
                    metadata: [
                        "requestType": requestType,
                        "requestId": requestId.uuidString,
                        "reason": result.error ?? "unknown"
                    ]
                )
                throw AppError.processingError("claim_complete_error_state".localized)
            }

            // Note: Review prompt will be handled by the UI layer
            await PerformanceMonitor.shared.record(
                operation: "claim.complete.success",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString
                ],
                slowThreshold: Constants.Performance.claimOperationSlowThreshold
            )
        } catch {
            await PerformanceMonitor.shared.record(
                operation: "claim.complete.failed",
                duration: Date().timeIntervalSince(operationStart),
                metadata: [
                    "requestType": requestType,
                    "requestId": requestId.uuidString,
                    "error": error.localizedDescription
                ]
            )
            throw error
        }
    }
    
}

extension ClaimService: ClaimServiceProtocol {}
