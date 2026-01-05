//
//  InviteCode.swift
//  NaarsCars
//
//  Invite code model matching database schema
//

import Foundation

/// Invite code model
struct InviteCode: Codable, Identifiable, Equatable {
    let id: UUID
    let code: String
    let createdBy: UUID
    let usedBy: UUID?
    let usedAt: Date?
    let createdAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case code
        case createdBy = "created_by"
        case usedBy = "used_by"
        case usedAt = "used_at"
        case createdAt = "created_at"
    }
    
    // MARK: - Computed Properties
    
    var isUsed: Bool {
        return usedAt != nil
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        code: String,
        createdBy: UUID,
        usedBy: UUID? = nil,
        usedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.code = code
        self.createdBy = createdBy
        self.usedBy = usedBy
        self.usedAt = usedAt
        self.createdAt = createdAt
    }
}


