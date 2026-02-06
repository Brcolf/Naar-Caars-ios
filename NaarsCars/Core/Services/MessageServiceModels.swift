//
//  MessageServiceModels.swift
//  NaarsCars
//
//  Model types used by MessageService
//

import Foundation

// MARK: - MessageService Model Types

extension MessageService {
    
    // MARK: - Unread Message Helpers
    
    struct MessageReadByRow: Decodable, Equatable {
        let id: UUID
        let readBy: [UUID]
        
        enum CodingKeys: String, CodingKey {
            case id
            case readBy = "read_by"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            readBy = try container.decodeIfPresent([UUID].self, forKey: .readBy) ?? []
        }
    }
    
    static func decodeUnreadMessages(from data: Data) throws -> [MessageReadByRow] {
        try JSONDecoder().decode([MessageReadByRow].self, from: data)
    }
    
    /// Build a PostgREST filter for unread read_by arrays.
    /// Includes null read_by and arrays that don't contain the user.
    static func unreadReadByFilter(userId: UUID) -> String {
        "read_by.is.null,read_by.not.cs.{\(userId.uuidString)}"
    }
    
    // MARK: - Reporting
    
    /// Report type enum
    enum ReportType: String {
        case spam
        case harassment
        case inappropriateContent = "inappropriate_content"
        case scam
        case other
    }
}
