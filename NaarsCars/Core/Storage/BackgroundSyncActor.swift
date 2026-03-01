//
//  BackgroundSyncActor.swift
//  NaarsCars
//
//  @ModelActor for off-MainActor SwiftData writes during sync engines.
//  SwiftUI @Query properties auto-update via persistent store observation.
//  Combine-backed publishers (messaging) are refreshed on MainActor after save.
//

import Foundation
import SwiftData

@ModelActor
actor BackgroundSyncActor {

    // MARK: - Public API

    /// Sync rides from network response to SwiftData
    func syncRides(_ rides: [Ride]) throws {
        syncRidesInternal(rides)
        try modelContext.save()
    }

    /// Sync favors from network response to SwiftData
    func syncFavors(_ favors: [Favor]) throws {
        syncFavorsInternal(favors)
        try modelContext.save()
    }

    /// Sync notifications from network response to SwiftData
    func syncNotifications(_ notifications: [AppNotification]) throws {
        syncNotificationsInternal(notifications)
        try modelContext.save()
    }

    /// Sync all three entity types in one save round-trip
    func syncAll(rides: [Ride], favors: [Favor], notifications: [AppNotification]) throws {
        syncRidesInternal(rides)
        syncFavorsInternal(favors)
        syncNotificationsInternal(notifications)
        try modelContext.save()
    }

    /// Sync conversations (and their last messages) from network response to SwiftData.
    /// Returns the set of conversation IDs that were changed so the caller can refresh publishers.
    func syncConversations(_ payloads: [ConversationSyncPayload], currentUserId: UUID) throws -> Set<UUID> {
        var changedIds = Set<UUID>()

        // Batch fetch all existing SDConversations and SDMessages at once
        let allLocalConvs = (try? modelContext.fetch(FetchDescriptor<SDConversation>())) ?? []
        let existingConvById = Dictionary(uniqueKeysWithValues: allLocalConvs.map { ($0.id, $0) })

        let allLocalMsgs = (try? modelContext.fetch(FetchDescriptor<SDMessage>())) ?? []
        let existingMsgById = Dictionary(uniqueKeysWithValues: allLocalMsgs.map { ($0.id, $0) })

        let serverConvIds = Set(payloads.map { $0.conversationId })

        for payload in payloads {
            changedIds.insert(payload.conversationId)

            // Upsert conversation
            if let existing = existingConvById[payload.conversationId] {
                existing.title = payload.title
                existing.groupImageUrl = payload.groupImageUrl
                existing.isArchived = payload.isArchived
                existing.updatedAt = payload.updatedAt
                existing.unreadCount = payload.unreadCount
                existing.participantIds = payload.participantIds
            } else {
                let newSDConv = SDConversation(
                    id: payload.conversationId,
                    title: payload.title,
                    groupImageUrl: payload.groupImageUrl,
                    createdBy: payload.createdBy,
                    isArchived: payload.isArchived,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt,
                    participantIds: payload.participantIds
                )
                newSDConv.unreadCount = payload.unreadCount
                modelContext.insert(newSDConv)
            }

            // Upsert last message if present
            if let msg = payload.lastMessage {
                upsertSDMessage(msg, existingById: existingMsgById, conversationId: payload.conversationId)
            }
        }

        // Delete stale conversations not on server
        for local in allLocalConvs where !serverConvIds.contains(local.id) {
            modelContext.delete(local)
            changedIds.insert(local.id)
        }

        try modelContext.save()
        return changedIds
    }

    // MARK: - Internal sync logic

    /// Upsert a single SDMessage using a pre-fetched lookup dictionary.
    /// Intentionally does NOT manage publisher state — that stays on MainActor.
    private func upsertSDMessage(_ message: Message, existingById: [UUID: SDMessage], conversationId: UUID) {
        if let existing = existingById[message.id] {
            existing.text = message.text
            existing.readBy = message.readBy
            existing.imageUrl = message.imageUrl
            existing.audioUrl = message.audioUrl
            existing.audioDuration = message.audioDuration
            existing.latitude = message.latitude
            existing.longitude = message.longitude
            existing.locationName = message.locationName
            existing.messageType = message.messageType?.rawValue ?? "text"
            existing.replyToId = message.replyToId
            existing.editedAt = message.editedAt
            existing.deletedAt = message.deletedAt
            existing.status = message.sendStatus?.rawValue ?? "sent"
            existing.localAttachmentPath = message.localAttachmentPath
            existing.syncError = message.syncError
            existing.isPending = (message.sendStatus?.rawValue ?? "sent") == "sending"
        } else {
            let sdMsg = MessagingMapper.mapToSDMessage(message)
            // Link to conversation if it exists in this context
            let convId = conversationId
            let convFetch = FetchDescriptor<SDConversation>(predicate: #Predicate { $0.id == convId })
            if let sdConv = try? modelContext.fetch(convFetch).first {
                sdMsg.conversation = sdConv
            }
            modelContext.insert(sdMsg)
        }
    }

    private func syncRidesInternal(_ rides: [Ride]) {
        guard !rides.isEmpty else { return }

        // Single batch fetch: get ALL existing SDRides at once
        let allLocal = (try? modelContext.fetch(FetchDescriptor<SDRide>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let serverIds = Set(rides.map { $0.id })

        // Upsert
        for ride in rides {
            if let existing = existingById[ride.id] {
                updateSDRide(existing, with: ride)
            } else {
                let sdRide = SDRide(
                    id: ride.id,
                    userId: ride.userId,
                    type: ride.type,
                    date: ride.date,
                    time: ride.time,
                    pickup: ride.pickup,
                    destination: ride.destination,
                    seats: ride.seats,
                    notes: ride.notes,
                    gift: ride.gift,
                    status: ride.status.rawValue,
                    claimedBy: ride.claimedBy,
                    reviewed: ride.reviewed,
                    reviewSkipped: ride.reviewSkipped,
                    reviewSkippedAt: ride.reviewSkippedAt,
                    estimatedCost: ride.estimatedCost,
                    flightNormalized: ride.flightNormalized,
                    createdAt: ride.createdAt,
                    updatedAt: ride.updatedAt,
                    posterName: ride.poster?.name,
                    posterAvatarUrl: ride.poster?.avatarUrl,
                    claimerName: ride.claimer?.name,
                    claimerAvatarUrl: ride.claimer?.avatarUrl,
                    participantIds: ride.participants?.map { $0.id } ?? [],
                    qaCount: ride.qaCount ?? 0
                )
                modelContext.insert(sdRide)
            }
        }

        // Delete stale (reuse allLocal from batch fetch)
        for local in allLocal where !serverIds.contains(local.id) {
            modelContext.delete(local)
        }
    }

    private func syncFavorsInternal(_ favors: [Favor]) {
        guard !favors.isEmpty else { return }

        // Single batch fetch: get ALL existing SDFavors at once
        let allLocal = (try? modelContext.fetch(FetchDescriptor<SDFavor>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let serverIds = Set(favors.map { $0.id })

        // Upsert
        for favor in favors {
            if let existing = existingById[favor.id] {
                updateSDFavor(existing, with: favor)
            } else {
                let sdFavor = SDFavor(
                    id: favor.id,
                    userId: favor.userId,
                    title: favor.title,
                    favorDescription: favor.description,
                    location: favor.location,
                    duration: favor.duration.rawValue,
                    requirements: favor.requirements,
                    date: favor.date,
                    time: favor.time,
                    gift: favor.gift,
                    status: favor.status.rawValue,
                    claimedBy: favor.claimedBy,
                    reviewed: favor.reviewed,
                    reviewSkipped: favor.reviewSkipped,
                    reviewSkippedAt: favor.reviewSkippedAt,
                    createdAt: favor.createdAt,
                    updatedAt: favor.updatedAt,
                    posterName: favor.poster?.name,
                    posterAvatarUrl: favor.poster?.avatarUrl,
                    claimerName: favor.claimer?.name,
                    claimerAvatarUrl: favor.claimer?.avatarUrl,
                    participantIds: favor.participants?.map { $0.id } ?? [],
                    qaCount: favor.qaCount ?? 0
                )
                modelContext.insert(sdFavor)
            }
        }

        // Delete stale (reuse allLocal from batch fetch)
        for local in allLocal where !serverIds.contains(local.id) {
            modelContext.delete(local)
        }
    }

    private func syncNotificationsInternal(_ notifications: [AppNotification]) {
        guard !notifications.isEmpty else { return }

        // Single batch fetch: get ALL existing SDNotifications at once
        let allLocal = (try? modelContext.fetch(FetchDescriptor<SDNotification>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        // Upsert
        for notification in notifications {
            if let existing = existingById[notification.id] {
                existing.read = notification.read
                existing.pinned = notification.pinned
                existing.title = notification.title
                existing.body = notification.body
            } else {
                let sd = SDNotification(
                    id: notification.id,
                    userId: notification.userId,
                    type: notification.type.rawValue,
                    title: notification.title,
                    body: notification.body,
                    read: notification.read,
                    pinned: notification.pinned,
                    createdAt: notification.createdAt,
                    rideId: notification.rideId,
                    favorId: notification.favorId,
                    conversationId: notification.conversationId,
                    reviewId: notification.reviewId,
                    townHallPostId: notification.townHallPostId,
                    sourceUserId: notification.sourceUserId
                )
                modelContext.insert(sd)
            }
        }
    }

    // MARK: - Field update helpers

    private func updateSDRide(_ sd: SDRide, with ride: Ride) {
        sd.status = ride.status.rawValue
        sd.claimedBy = ride.claimedBy
        sd.updatedAt = ride.updatedAt
        sd.qaCount = ride.qaCount ?? 0
        sd.date = ride.date
        sd.time = ride.time
        sd.pickup = ride.pickup
        sd.destination = ride.destination
        sd.seats = ride.seats
        sd.notes = ride.notes
        sd.gift = ride.gift
        sd.reviewed = ride.reviewed
        sd.reviewSkipped = ride.reviewSkipped
        sd.reviewSkippedAt = ride.reviewSkippedAt
        sd.estimatedCost = ride.estimatedCost
        sd.flightNormalized = ride.flightNormalized
        sd.posterName = ride.poster?.name
        sd.posterAvatarUrl = ride.poster?.avatarUrl
        sd.claimerName = ride.claimer?.name
        sd.claimerAvatarUrl = ride.claimer?.avatarUrl
        sd.participantIds = ride.participants?.map { $0.id } ?? []
    }

    private func updateSDFavor(_ sd: SDFavor, with favor: Favor) {
        sd.status = favor.status.rawValue
        sd.claimedBy = favor.claimedBy
        sd.updatedAt = favor.updatedAt
        sd.qaCount = favor.qaCount ?? 0
        sd.title = favor.title
        sd.favorDescription = favor.description
        sd.location = favor.location
        sd.duration = favor.duration.rawValue
        sd.requirements = favor.requirements
        sd.date = favor.date
        sd.time = favor.time
        sd.gift = favor.gift
        sd.reviewed = favor.reviewed
        sd.reviewSkipped = favor.reviewSkipped
        sd.reviewSkippedAt = favor.reviewSkippedAt
        sd.posterName = favor.poster?.name
        sd.posterAvatarUrl = favor.poster?.avatarUrl
        sd.claimerName = favor.claimer?.name
        sd.claimerAvatarUrl = favor.claimer?.avatarUrl
        sd.participantIds = favor.participants?.map { $0.id } ?? []
    }
}

// MARK: - Conversation sync payload

/// Lightweight, Sendable value type for passing conversation data across actor boundaries.
/// Extracted from ConversationWithDetails on MainActor before being sent to BackgroundSyncActor.
struct ConversationSyncPayload: Sendable {
    let conversationId: UUID
    let title: String?
    let groupImageUrl: String?
    let createdBy: UUID
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let participantIds: [UUID]
    let unreadCount: Int
    let lastMessage: Message?

    init(from remote: ConversationWithDetails, currentUserId: UUID) {
        self.conversationId = remote.conversation.id
        self.title = remote.conversation.title
        self.groupImageUrl = remote.conversation.groupImageUrl
        self.createdBy = remote.conversation.createdBy
        self.isArchived = remote.conversation.isArchived
        self.createdAt = remote.conversation.createdAt
        self.updatedAt = remote.conversation.updatedAt
        self.unreadCount = remote.unreadCount
        self.lastMessage = remote.lastMessage
        // Collect participant IDs from otherParticipants + current user
        self.participantIds = remote.otherParticipants.map { $0.id } + [currentUserId]
    }
}
