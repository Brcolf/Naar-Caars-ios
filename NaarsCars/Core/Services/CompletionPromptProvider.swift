//
//  CompletionPromptProvider.swift
//  NaarsCars
//
//  Real implementation of CompletionPromptProviding protocol
//

import Foundation
import Supabase

final class CompletionPromptProvider: CompletionPromptProviding {
    private let supabase = SupabaseService.shared.client
    private let rideService = RideService.shared
    private let favorService = FavorService.shared

    func fetchDueCompletionPrompts(userId: UUID) async throws -> [CompletionPrompt] {
        let response = try await supabase
            .from("completion_reminders")
            .select("*")
            .eq("claimer_user_id", value: userId.uuidString)
            .eq("completed", value: false)
            .lte("scheduled_for", value: ISO8601DateFormatter().string(from: Date()))
            .order("scheduled_for", ascending: true)
            .execute()

        let decoder = JSONDecoderFactory.createSupabaseDecoder()
        let reminders = try decoder.decode([CompletionReminder].self, from: response.data)
        return try await buildPrompts(from: reminders)
    }

    func fetchCompletionPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> CompletionPrompt? {
        let response = try await supabase
            .from("completion_reminders")
            .select("*")
            .eq("claimer_user_id", value: userId.uuidString)
            .eq("completed", value: false)
            .eq(requestType == .ride ? "ride_id" : "favor_id", value: requestId.uuidString)
            .order("scheduled_for", ascending: true)
            .limit(1)
            .execute()

        let decoder = JSONDecoderFactory.createSupabaseDecoder()
        let reminders = try decoder.decode([CompletionReminder].self, from: response.data)
        return try await buildPrompts(from: reminders).first
    }

    private func buildPrompts(from reminders: [CompletionReminder]) async throws -> [CompletionPrompt] {
        var prompts: [CompletionPrompt] = []
        for reminder in reminders {
            if let rideId = reminder.rideId {
                let ride = try await rideService.fetchRide(id: rideId)
                prompts.append(CompletionPrompt(
                    id: reminder.id,
                    reminderId: reminder.id,
                    requestType: .ride,
                    requestId: rideId,
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    dueAt: reminder.scheduledFor
                ))
            } else if let favorId = reminder.favorId {
                let favor = try await favorService.fetchFavor(id: favorId)
                prompts.append(CompletionPrompt(
                    id: reminder.id,
                    reminderId: reminder.id,
                    requestType: .favor,
                    requestId: favorId,
                    requestTitle: favor.title,
                    dueAt: reminder.scheduledFor
                ))
            }
        }
        return prompts
    }
}

private struct CompletionReminder: Decodable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    let scheduledFor: Date

    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case scheduledFor = "scheduled_for"
    }
}

