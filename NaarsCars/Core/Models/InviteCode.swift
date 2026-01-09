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
    
    // MARK: - Computed Properties
    
    var isUsed: Bool {
        return usedBy != nil
    }
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
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

