//
//  ConversationMuteService.swift
//  NaarsCars
//
//  Manages per-conversation mute state in the database
//

import Foundation
import Supabase

final class ConversationMuteService {
    static let shared = ConversationMuteService()
    private let supabase = SupabaseService.shared.client
    private init() {}

    enum MuteDuration: CaseIterable {
        case oneHour
        case eightHours
        case twentyFourHours
        case indefinitely

        var interval: TimeInterval? {
            switch self {
            case .oneHour: return 3600
            case .eightHours: return 28800
            case .twentyFourHours: return 86400
            case .indefinitely: return nil
            }
        }

        var displayName: String {
            switch self {
            case .oneHour: return "messaging_mute_1_hour".localized
            case .eightHours: return "messaging_mute_8_hours".localized
            case .twentyFourHours: return "messaging_mute_24_hours".localized
            case .indefinitely: return "messaging_mute_indefinitely".localized
            }
        }
    }

    func muteConversation(conversationId: UUID, userId: UUID, duration: MuteDuration) async throws {
        var updates: [String: AnyCodable] = [
            "notifications_muted": AnyCodable(true)
        ]
        if let interval = duration.interval {
            let until = Date().addingTimeInterval(interval)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            updates["muted_until"] = AnyCodable(formatter.string(from: until))
        } else {
            updates["muted_until"] = AnyCodable(nil as String? as Any)
        }

        try await supabase
            .from("conversation_participants")
            .update(updates)
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func unmuteConversation(conversationId: UUID, userId: UUID) async throws {
        let updates: [String: AnyCodable] = [
            "notifications_muted": AnyCodable(false),
            "muted_until": AnyCodable(nil as String? as Any)
        ]

        try await supabase
            .from("conversation_participants")
            .update(updates)
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func isMuted(conversationId: UUID, userId: UUID) async -> Bool {
        guard let resp = try? await supabase
            .from("conversation_participants")
            .select("notifications_muted, muted_until")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .is("left_at", value: nil)
            .single()
            .execute() else { return false }

        struct MuteRow: Codable {
            let notificationsMuted: Bool
            let mutedUntil: Date?
            enum CodingKeys: String, CodingKey {
                case notificationsMuted = "notifications_muted"
                case mutedUntil = "muted_until"
            }
        }
        guard let row = try? DateDecoderFactory.makeMessagingDecoder().decode(MuteRow.self, from: resp.data) else {
            return false
        }
        if row.notificationsMuted { return true }
        if let until = row.mutedUntil, until > Date() { return true }
        return false
    }

    /// Fetch mute status for multiple conversations at once (used by conversation list)
    func fetchMutedConversationIds(userId: UUID) async -> Set<UUID> {
        guard let resp = try? await supabase
            .from("conversation_participants")
            .select("conversation_id, notifications_muted, muted_until")
            .eq("user_id", value: userId.uuidString)
            .is("left_at", value: nil)
            .execute() else { return [] }

        struct MuteRow: Codable {
            let conversationId: UUID
            let notificationsMuted: Bool
            let mutedUntil: Date?
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case notificationsMuted = "notifications_muted"
                case mutedUntil = "muted_until"
            }
        }
        guard let rows = try? DateDecoderFactory.makeMessagingDecoder().decode([MuteRow].self, from: resp.data) else {
            return []
        }
        let now = Date()
        return Set(rows.filter { row in
            if row.notificationsMuted { return true }
            if let until = row.mutedUntil, until > now { return true }
            return false
        }.map { $0.conversationId })
    }
}
