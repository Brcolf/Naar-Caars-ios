//
//  InviteCode.swift
//  NaarsCars
//
//  Invite code model matching database schema
//

import Foundation

/// Invite code model
struct InviteCode: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let code: String
    let createdBy: UUID
    let usedBy: UUID?
    let usedAt: Date?
    let createdAt: Date
    let inviteStatement: String?
    let isBulk: Bool
    let expiresAt: Date?
    let bulkCodeId: UUID?
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case code
        case createdBy = "created_by"
        case usedBy = "used_by"
        case usedAt = "used_at"
        case createdAt = "created_at"
        case inviteStatement = "invite_statement"
        case isBulk = "is_bulk"
        case expiresAt = "expires_at"
        case bulkCodeId = "bulk_code_id"
    }
    
    // MARK: - Custom Decoding
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        usedBy = try container.decodeIfPresent(UUID.self, forKey: .usedBy)
        usedAt = try container.decodeIfPresent(Date.self, forKey: .usedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        inviteStatement = try container.decodeIfPresent(String.self, forKey: .inviteStatement)
        
        // Handle is_bulk: default to false if null (for backward compatibility with old rows)
        isBulk = try container.decodeIfPresent(Bool.self, forKey: .isBulk) ?? false
        
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        bulkCodeId = try container.decodeIfPresent(UUID.self, forKey: .bulkCodeId)
    }
    
    // MARK: - Custom Encoding
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(usedBy, forKey: .usedBy)
        try container.encodeIfPresent(usedAt, forKey: .usedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(inviteStatement, forKey: .inviteStatement)
        try container.encode(isBulk, forKey: .isBulk)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(bulkCodeId, forKey: .bulkCodeId)
    }
    
    // MARK: - Computed Properties
    
    var isUsed: Bool {
        return usedBy != nil
    }
    
    /// Check if the invite code is expired
    /// Non-bulk codes (expiresAt == nil) never expire
    /// Bulk codes expire after expiresAt date
    var isExpired: Bool {
        guard let expiresAt = expiresAt else {
            // Non-bulk codes don't expire (expiresAt is nil)
            return false
        }
        return Date() > expiresAt
    }
    
    /// Check if the invite code is active (not used and not expired)
    var isActive: Bool {
        return !isUsed && !isExpired
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        code: String,
        createdBy: UUID,
        usedBy: UUID? = nil,
        usedAt: Date? = nil,
        createdAt: Date = Date(),
        inviteStatement: String? = nil,
        isBulk: Bool = false,
        expiresAt: Date? = nil,
        bulkCodeId: UUID? = nil
    ) {
        self.id = id
        self.code = code
        self.createdBy = createdBy
        self.usedBy = usedBy
        self.usedAt = usedAt
        self.createdAt = createdAt
        self.inviteStatement = inviteStatement
        self.isBulk = isBulk
        self.expiresAt = expiresAt
        self.bulkCodeId = bulkCodeId
    }
}
