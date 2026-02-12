//
//  InviteService.swift
//  NaarsCars
//
//  Service for invite code operations
//  Handles generation, fetching, and statistics for invite codes
//

import Foundation
import Supabase

/// Service for invite code operations
/// Handles generation with rate limiting, fetching with invitee info, and statistics
final class InviteService {
    
    // MARK: - Singleton
    
    static let shared = InviteService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Invite Code Operations
    
    /// Fetch current active invite code for a user (only one at a time)
    /// Returns the most recent active (unused, not expired) code
    /// - Parameter userId: The user ID
    /// - Returns: Current active invite code with invitee info, or nil if none exists
    /// - Throws: AppError if fetch fails
    func fetchCurrentInviteCode(userId: UUID) async throws -> InviteCodeWithInvitee? {
        // Fetch only active codes (unused, not expired)
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = dateFormatter.string(from: now)
        
        // Query for active codes: used_by IS NULL AND (expires_at IS NULL OR expires_at > NOW())
        let codes: [InviteCode] = try await supabase
            .from("invite_codes")
            .select()
            .eq("created_by", value: userId.uuidString)
            .is("used_by", value: nil)
            .or("expires_at.is.null,expires_at.gt.\(nowString)")
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        
        // Filter out expired codes in Swift (more reliable)
        let activeCodes = codes.filter { !$0.isExpired }
        
        guard let code = activeCodes.first else {
            return nil
        }
        
        // Enrich with invitee information if used (shouldn't happen for active codes, but handle it)
        var inviteeName: String? = nil
        if let usedById = code.usedBy {
            if let inviteeProfile: Profile = try? await supabase
                .from("profiles")
                .select()
                .eq("id", value: usedById.uuidString)
                .single()
                .execute()
                .value {
                inviteeName = inviteeProfile.name
            }
        }
        
        return InviteCodeWithInvitee(
            inviteCode: code,
            inviteeName: inviteeName
        )
    }
    
    /// Generate a new invite code for a user (single-use, with invitation statement)
    /// Only one active code allowed per user - deactivates any existing active code
    /// - Parameters:
    ///   - userId: The user ID
    ///   - inviteStatement: Statement explaining who they're inviting and why
    /// - Returns: The newly created invite code
    /// - Throws: AppError if generation fails
    func generateInviteCode(userId: UUID, inviteStatement: String) async throws -> InviteCode {
        // Check if user already has an active code
        // If so, we'll mark it as "replaced" by creating a new one
        // (Old code remains in DB but won't be shown in UI)
        
        // Generate secure 8-character code
        let code = InviteCodeGenerator.generate()
        
        // Check for uniqueness (though extremely unlikely with 32^8 combinations)
        // If collision, retry (max 3 attempts)
        var attempts = 0
        var finalCode = code
        
        while attempts < 3 {
            let existingCheck = try? await supabase
                .from("invite_codes")
                .select("id", head: true, count: .exact)
                .eq("code", value: finalCode)
                .execute()
            
            if (existingCheck?.count ?? 0) == 0 {
                break // Code is unique
            }
            
            // Collision - generate new code
            finalCode = InviteCodeGenerator.generate()
            attempts += 1
        }
        
        // Create new invite code (single-use, not bulk)
        let newCode = InviteCode(
            id: UUID(),
            code: finalCode,
            createdBy: userId,
            usedBy: nil,
            usedAt: nil,
            createdAt: Date(),
            inviteStatement: inviteStatement,
            isBulk: false,
            expiresAt: nil,
            bulkCodeId: nil
        )
        
        let insertedCode: InviteCode = try await supabase
            .from("invite_codes")
            .insert(newCode)
            .select()
            .single()
            .execute()
            .value
        
        return insertedCode
    }
    
    /// Generate a bulk invite code for an admin (multiple uses, expires in 48 hours)
    /// - Parameter userId: The admin user ID
    /// - Returns: The newly created bulk invite code
    /// - Throws: AppError if generation fails or user is not admin
    func generateBulkInviteCode(userId: UUID) async throws -> InviteCode {
        // Verify user is admin
        let profile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        guard profile.isAdmin else {
            throw AppError.permissionDenied("Only admins can generate bulk invite codes")
        }
        
        // Generate secure 8-character code
        let code = InviteCodeGenerator.generate()
        
        // Check for uniqueness
        var attempts = 0
        var finalCode = code
        
        while attempts < 3 {
            let existingCheck = try? await supabase
                .from("invite_codes")
                .select("id", head: true, count: .exact)
                .eq("code", value: finalCode)
                .execute()
            
            if (existingCheck?.count ?? 0) == 0 {
                break
            }
            
            finalCode = InviteCodeGenerator.generate()
            attempts += 1
        }
        
        // Create bulk invite code (expires in 48 hours)
        let expiresAt = Calendar.current.date(byAdding: .hour, value: 48, to: Date())!
        
        let newCode = InviteCode(
            id: UUID(),
            code: finalCode,
            createdBy: userId,
            usedBy: nil,
            usedAt: nil,
            createdAt: Date(),
            inviteStatement: nil, // No statement for bulk invites
            isBulk: true,
            expiresAt: expiresAt,
            bulkCodeId: nil // This is the bulk code itself
        )
        
        let insertedCode: InviteCode = try await supabase
            .from("invite_codes")
            .insert(newCode)
            .select()
            .single()
            .execute()
            .value
        
        return insertedCode
    }
    
    /// Get invite statistics for a user
    /// - Parameter userId: The user ID
    /// - Returns: InviteStats with codes created and codes used counts
    /// - Throws: AppError if fetch fails
    func getInviteStats(userId: UUID) async throws -> InviteStats {
        // Count total codes created
        let totalResponse = try await supabase
            .from("invite_codes")
            .select("id", head: true, count: .exact)
            .eq("created_by", value: userId.uuidString)
            .execute()
        
        let totalCreated = totalResponse.count ?? 0
        
        // Count used codes (filter in Swift since PostgREST doesn't support not null easily)
        // Fetch all codes and count those with used_by
        let allCodes: [InviteCode] = try await supabase
            .from("invite_codes")
            .select()
            .eq("created_by", value: userId.uuidString)
            .execute()
            .value
        
        let totalUsed = allCodes.filter { $0.usedBy != nil }.count
        
        return InviteStats(
            codesCreated: totalCreated,
            codesUsed: totalUsed
        )
    }
    
    /// Mark an invite code as used (or create tracking record for bulk codes)
    /// - Parameters:
    ///   - inviteCode: The invite code that was used
    ///   - userId: The user ID who used the code
    /// - Throws: AppError if update fails
    func markInviteCodeAsUsed(inviteCode: InviteCode, userId: UUID) async throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let usedAtString = dateFormatter.string(from: Date())
        
        if inviteCode.isBulk {
            // For bulk codes: Create a tracking record (bulk code itself remains active)
            struct BulkInviteRecord: Codable {
                let id: String
                let code: String
                let createdBy: String
                let usedBy: String
                let usedAt: String
                let createdAt: String
                let isBulk: Bool
                let bulkCodeId: String
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case code
                    case createdBy = "created_by"
                    case usedBy = "used_by"
                    case usedAt = "used_at"
                    case createdAt = "created_at"
                    case isBulk = "is_bulk"
                    case bulkCodeId = "bulk_code_id"
                }
            }
            
            // Generate tracking code for this individual signup
            let trackingCode = "\(inviteCode.code)-\(UUID().uuidString.prefix(8).uppercased())"
            let newRecordId = UUID()
            
            let bulkRecord = BulkInviteRecord(
                id: newRecordId.uuidString,
                code: trackingCode,
                createdBy: inviteCode.createdBy.uuidString,
                usedBy: userId.uuidString,
                usedAt: usedAtString,
                createdAt: usedAtString, // Use same timestamp for created_at
                isBulk: false,
                bulkCodeId: inviteCode.id.uuidString
            )
            
            try await supabase
                .from("invite_codes")
                .insert(bulkRecord)
                .execute()
        } else {
            // Regular code: Mark as used (single-use)
            struct InviteCodeUpdate: Codable {
                let usedBy: String
                let usedAt: String
                
                enum CodingKeys: String, CodingKey {
                    case usedBy = "used_by"
                    case usedAt = "used_at"
                }
            }
            
            let inviteUpdate = InviteCodeUpdate(
                usedBy: userId.uuidString,
                usedAt: usedAtString
            )
            
            try await supabase
                .from("invite_codes")
                .update(inviteUpdate)
                .eq("id", value: inviteCode.id.uuidString)
                .execute()
        }
    }
    
    /// Fetch invite code details for a user (used for admin approval view)
    /// Finds the invite code that was used by this user
    /// - Parameter userId: The user ID who signed up
    /// - Returns: Invite code with inviter profile and statement, or nil if not found
    /// - Throws: AppError if fetch fails
    func fetchInviteCodeForUser(userId: UUID) async throws -> (inviteCode: InviteCode, inviter: Profile?, statement: String?)? {
        // Find invite code used by this user
        let codes: [InviteCode] = try await supabase
            .from("invite_codes")
            .select()
            .eq("used_by", value: userId.uuidString)
            .order("used_at", ascending: false)
            .limit(1)
            .execute()
            .value
        
        guard let code = codes.first else {
            return nil
        }
        
        // Fetch inviter profile (the one who created the code)
        var inviter: Profile? = nil
        if let inviterId = code.bulkCodeId {
            // For bulk codes, fetch the bulk code creator
            if let bulkCode: InviteCode = try? await supabase
                .from("invite_codes")
                .select()
                .eq("id", value: inviterId.uuidString)
                .single()
                .execute()
                .value {
                inviter = try? await supabase
                    .from("profiles")
                    .select()
                    .eq("id", value: bulkCode.createdBy.uuidString)
                    .single()
                    .execute()
                    .value
            }
        } else {
            // Regular code: fetch creator
            inviter = try? await supabase
                .from("profiles")
                .select()
                .eq("id", value: code.createdBy.uuidString)
                .single()
                .execute()
                .value
        }
        
        // Get statement from the original code (for bulk codes, check the bulk code)
        var statement: String? = code.inviteStatement
        if statement == nil, let bulkCodeId = code.bulkCodeId {
            if let bulkCode: InviteCode = try? await supabase
                .from("invite_codes")
                .select()
                .eq("id", value: bulkCodeId.uuidString)
                .single()
                .execute()
                .value {
                statement = bulkCode.inviteStatement
            }
        }
        
        return (code, inviter, statement)
    }
}

// MARK: - Supporting Types

/// Invite code with invitee information for display
struct InviteCodeWithInvitee: Identifiable, Equatable {
    let inviteCode: InviteCode
    let inviteeName: String?
    
    var id: UUID { inviteCode.id }
    var code: String { inviteCode.code }
    var createdBy: UUID { inviteCode.createdBy }
    var usedBy: UUID? { inviteCode.usedBy }
    var usedAt: Date? { inviteCode.usedAt }
    var createdAt: Date { inviteCode.createdAt }
    var isUsed: Bool { inviteCode.isUsed }
}

/// Invite statistics for a user
struct InviteStats: Equatable {
    let codesCreated: Int
    let codesUsed: Int
    
    var codesAvailable: Int {
        codesCreated - codesUsed
    }
}

