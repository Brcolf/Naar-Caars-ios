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

    /// Upsert a single ride from a realtime payload (incremental update).
    /// Preserves existing joined fields (poster, claimer, participants, qaCount) that
    /// are not present in realtime payloads.
    func upsertRide(_ ride: Ride) throws {
        let rideId = ride.id
        let predicate = #Predicate<SDRide> { $0.id == rideId }
        let descriptor = FetchDescriptor<SDRide>(predicate: predicate)
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update core fields from realtime payload
            existing.status = ride.status.rawValue
            existing.claimedBy = ride.claimedBy
            existing.updatedAt = ride.updatedAt
            existing.date = ride.date
            existing.time = ride.time
            existing.timezone = ride.timezone
            existing.pickup = ride.pickup
            existing.destination = ride.destination
            existing.seats = ride.seats
            existing.notes = ride.notes
            existing.gift = ride.gift
            existing.reviewed = ride.reviewed
            existing.reviewSkipped = ride.reviewSkipped
            existing.reviewSkippedAt = ride.reviewSkippedAt
            existing.estimatedCost = ride.estimatedCost
            existing.flightNormalized = ride.flightNormalized
            existing.hiddenAt = ride.hiddenAt
            existing.hiddenBy = ride.hiddenBy
            existing.hiddenReason = ride.hiddenReason
            // Preserve poster/claimer/participants/qaCount — not in realtime payloads
        } else {
            let sdRide = SDRide(
                id: ride.id,
                userId: ride.userId,
                type: ride.type,
                date: ride.date,
                time: ride.time,
                timezone: ride.timezone,
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
                hiddenAt: ride.hiddenAt,
                hiddenBy: ride.hiddenBy,
                hiddenReason: ride.hiddenReason,
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
        try modelContext.save()
    }

    /// Upsert a single favor from a realtime payload (incremental update).
    /// Preserves existing joined fields that are not present in realtime payloads.
    func upsertFavor(_ favor: Favor) throws {
        let favorId = favor.id
        let predicate = #Predicate<SDFavor> { $0.id == favorId }
        let descriptor = FetchDescriptor<SDFavor>(predicate: predicate)
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update core fields from realtime payload
            existing.status = favor.status.rawValue
            existing.claimedBy = favor.claimedBy
            existing.updatedAt = favor.updatedAt
            existing.title = favor.title
            existing.favorDescription = favor.description
            existing.location = favor.location
            existing.duration = favor.duration.rawValue
            existing.requirements = favor.requirements
            existing.date = favor.date
            existing.time = favor.time
            existing.timezone = favor.timezone
            existing.gift = favor.gift
            existing.reviewed = favor.reviewed
            existing.reviewSkipped = favor.reviewSkipped
            existing.reviewSkippedAt = favor.reviewSkippedAt
            existing.hiddenAt = favor.hiddenAt
            existing.hiddenBy = favor.hiddenBy
            existing.hiddenReason = favor.hiddenReason
            // Preserve poster/claimer/participants/qaCount — not in realtime payloads
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
                timezone: favor.timezone,
                gift: favor.gift,
                status: favor.status.rawValue,
                claimedBy: favor.claimedBy,
                reviewed: favor.reviewed,
                reviewSkipped: favor.reviewSkipped,
                reviewSkippedAt: favor.reviewSkippedAt,
                hiddenAt: favor.hiddenAt,
                hiddenBy: favor.hiddenBy,
                hiddenReason: favor.hiddenReason,
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
        try modelContext.save()
    }

    /// Delete a single ride by ID (for realtime delete events)
    func deleteRide(id: UUID) throws {
        let predicate = #Predicate<SDRide> { $0.id == id }
        let descriptor = FetchDescriptor<SDRide>(predicate: predicate)
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    /// Delete a single favor by ID (for realtime delete events)
    func deleteFavor(id: UUID) throws {
        let predicate = #Predicate<SDFavor> { $0.id == id }
        let descriptor = FetchDescriptor<SDFavor>(predicate: predicate)
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    /// Upsert a single notification from a realtime payload (incremental update).
    func upsertNotification(_ notification: AppNotification) throws {
        let notifId = notification.id
        let predicate = #Predicate<SDNotification> { $0.id == notifId }
        let descriptor = FetchDescriptor<SDNotification>(predicate: predicate)
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.read = notification.read
            existing.pinned = notification.pinned
            existing.title = notification.title
            existing.body = notification.body
            existing.rideId = notification.rideId
            existing.favorId = notification.favorId
            existing.conversationId = notification.conversationId
            existing.reviewId = notification.reviewId
            existing.townHallPostId = notification.townHallPostId
            existing.sourceUserId = notification.sourceUserId
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
        try modelContext.save()
    }

    /// Delete a single notification by ID (for realtime delete events)
    func deleteNotification(id: UUID) throws {
        let predicate = #Predicate<SDNotification> { $0.id == id }
        let descriptor = FetchDescriptor<SDNotification>(predicate: predicate)
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
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
    func syncConversations(_ payloads: [ConversationSyncPayload], currentUserId: UUID, excludeMessagesForConversation: UUID? = nil) throws -> Set<UUID> {
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

            // Upsert last message if present — skip for active conversation
            // to avoid concurrent writes with MainActor WebSocket path (INV-C1)
            if let msg = payload.lastMessage,
               payload.conversationId != excludeMessagesForConversation {
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
            existing.hiddenAt = message.hiddenAt
            existing.hiddenBy = message.hiddenBy
            existing.hiddenReason = message.hiddenReason
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
                    timezone: ride.timezone,
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
                    hiddenAt: ride.hiddenAt,
                    hiddenBy: ride.hiddenBy,
                    hiddenReason: ride.hiddenReason,
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
                    timezone: favor.timezone,
                    gift: favor.gift,
                    status: favor.status.rawValue,
                    claimedBy: favor.claimedBy,
                    reviewed: favor.reviewed,
                    reviewSkipped: favor.reviewSkipped,
                    reviewSkippedAt: favor.reviewSkippedAt,
                    hiddenAt: favor.hiddenAt,
                    hiddenBy: favor.hiddenBy,
                    hiddenReason: favor.hiddenReason,
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
        sd.timezone = ride.timezone
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
        sd.hiddenAt = ride.hiddenAt
        sd.hiddenBy = ride.hiddenBy
        sd.hiddenReason = ride.hiddenReason
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
        sd.timezone = favor.timezone
        sd.gift = favor.gift
        sd.reviewed = favor.reviewed
        sd.reviewSkipped = favor.reviewSkipped
        sd.reviewSkippedAt = favor.reviewSkippedAt
        sd.hiddenAt = favor.hiddenAt
        sd.hiddenBy = favor.hiddenBy
        sd.hiddenReason = favor.hiddenReason
        sd.posterName = favor.poster?.name
        sd.posterAvatarUrl = favor.poster?.avatarUrl
        sd.claimerName = favor.claimer?.name
        sd.claimerAvatarUrl = favor.claimer?.avatarUrl
        sd.participantIds = favor.participants?.map { $0.id } ?? []
    }

    // MARK: - Change detection helpers

    /// Returns true if any field was actually modified.
    /// IMPORTANT: Must cover every field that updateSDRide assigns.
    /// When adding a field to SDRide, add the comparison here too.
    private func updateSDRideIfChanged(_ sd: SDRide, with ride: Ride) -> Bool {
        var changed = false
        if sd.status != ride.status.rawValue { sd.status = ride.status.rawValue; changed = true }
        if sd.claimedBy != ride.claimedBy { sd.claimedBy = ride.claimedBy; changed = true }
        if sd.updatedAt != ride.updatedAt { sd.updatedAt = ride.updatedAt; changed = true }
        if sd.qaCount != (ride.qaCount ?? 0) { sd.qaCount = ride.qaCount ?? 0; changed = true }
        if sd.date != ride.date { sd.date = ride.date; changed = true }
        if sd.time != ride.time { sd.time = ride.time; changed = true }
        if sd.timezone != ride.timezone { sd.timezone = ride.timezone; changed = true }
        if sd.pickup != ride.pickup { sd.pickup = ride.pickup; changed = true }
        if sd.destination != ride.destination { sd.destination = ride.destination; changed = true }
        if sd.seats != ride.seats { sd.seats = ride.seats; changed = true }
        if sd.notes != ride.notes { sd.notes = ride.notes; changed = true }
        if sd.gift != ride.gift { sd.gift = ride.gift; changed = true }
        if sd.reviewed != ride.reviewed { sd.reviewed = ride.reviewed; changed = true }
        if sd.reviewSkipped != ride.reviewSkipped { sd.reviewSkipped = ride.reviewSkipped; changed = true }
        if sd.reviewSkippedAt != ride.reviewSkippedAt { sd.reviewSkippedAt = ride.reviewSkippedAt; changed = true }
        if sd.estimatedCost != ride.estimatedCost { sd.estimatedCost = ride.estimatedCost; changed = true }
        if sd.flightNormalized != ride.flightNormalized { sd.flightNormalized = ride.flightNormalized; changed = true }
        if sd.hiddenAt != ride.hiddenAt { sd.hiddenAt = ride.hiddenAt; changed = true }
        if sd.hiddenBy != ride.hiddenBy { sd.hiddenBy = ride.hiddenBy; changed = true }
        if sd.hiddenReason != ride.hiddenReason { sd.hiddenReason = ride.hiddenReason; changed = true }
        if sd.posterName != ride.poster?.name { sd.posterName = ride.poster?.name; changed = true }
        if sd.posterAvatarUrl != ride.poster?.avatarUrl { sd.posterAvatarUrl = ride.poster?.avatarUrl; changed = true }
        if sd.claimerName != ride.claimer?.name { sd.claimerName = ride.claimer?.name; changed = true }
        if sd.claimerAvatarUrl != ride.claimer?.avatarUrl { sd.claimerAvatarUrl = ride.claimer?.avatarUrl; changed = true }
        let newParticipantIds = ride.participants?.map { $0.id } ?? []
        if sd.participantIds != newParticipantIds { sd.participantIds = newParticipantIds; changed = true }
        return changed
    }

    /// Returns true if any field was actually modified.
    private func updateSDFavorIfChanged(_ sd: SDFavor, with favor: Favor) -> Bool {
        var changed = false
        if sd.status != favor.status.rawValue { sd.status = favor.status.rawValue; changed = true }
        if sd.claimedBy != favor.claimedBy { sd.claimedBy = favor.claimedBy; changed = true }
        if sd.updatedAt != favor.updatedAt { sd.updatedAt = favor.updatedAt; changed = true }
        if sd.qaCount != (favor.qaCount ?? 0) { sd.qaCount = favor.qaCount ?? 0; changed = true }
        if sd.title != favor.title { sd.title = favor.title; changed = true }
        if sd.favorDescription != favor.description { sd.favorDescription = favor.description; changed = true }
        if sd.location != favor.location { sd.location = favor.location; changed = true }
        if sd.duration != favor.duration.rawValue { sd.duration = favor.duration.rawValue; changed = true }
        if sd.requirements != favor.requirements { sd.requirements = favor.requirements; changed = true }
        if sd.date != favor.date { sd.date = favor.date; changed = true }
        if sd.time != favor.time { sd.time = favor.time; changed = true }
        if sd.timezone != favor.timezone { sd.timezone = favor.timezone; changed = true }
        if sd.gift != favor.gift { sd.gift = favor.gift; changed = true }
        if sd.reviewed != favor.reviewed { sd.reviewed = favor.reviewed; changed = true }
        if sd.reviewSkipped != favor.reviewSkipped { sd.reviewSkipped = favor.reviewSkipped; changed = true }
        if sd.reviewSkippedAt != favor.reviewSkippedAt { sd.reviewSkippedAt = favor.reviewSkippedAt; changed = true }
        if sd.hiddenAt != favor.hiddenAt { sd.hiddenAt = favor.hiddenAt; changed = true }
        if sd.hiddenBy != favor.hiddenBy { sd.hiddenBy = favor.hiddenBy; changed = true }
        if sd.hiddenReason != favor.hiddenReason { sd.hiddenReason = favor.hiddenReason; changed = true }
        if sd.posterName != favor.poster?.name { sd.posterName = favor.poster?.name; changed = true }
        if sd.posterAvatarUrl != favor.poster?.avatarUrl { sd.posterAvatarUrl = favor.poster?.avatarUrl; changed = true }
        if sd.claimerName != favor.claimer?.name { sd.claimerName = favor.claimer?.name; changed = true }
        if sd.claimerAvatarUrl != favor.claimer?.avatarUrl { sd.claimerAvatarUrl = favor.claimer?.avatarUrl; changed = true }
        let newParticipantIds = favor.participants?.map { $0.id } ?? []
        if sd.participantIds != newParticipantIds { sd.participantIds = newParticipantIds; changed = true }
        return changed
    }

    /// Returns true if any field was actually modified.
    private func updateSDNotificationIfChanged(_ sd: SDNotification, with notification: AppNotification) -> Bool {
        var changed = false
        if sd.read != notification.read { sd.read = notification.read; changed = true }
        if sd.pinned != notification.pinned { sd.pinned = notification.pinned; changed = true }
        if sd.title != notification.title { sd.title = notification.title; changed = true }
        if sd.body != notification.body { sd.body = notification.body; changed = true }
        if sd.rideId != notification.rideId { sd.rideId = notification.rideId; changed = true }
        if sd.favorId != notification.favorId { sd.favorId = notification.favorId; changed = true }
        if sd.conversationId != notification.conversationId { sd.conversationId = notification.conversationId; changed = true }
        if sd.reviewId != notification.reviewId { sd.reviewId = notification.reviewId; changed = true }
        if sd.townHallPostId != notification.townHallPostId { sd.townHallPostId = notification.townHallPostId; changed = true }
        if sd.sourceUserId != notification.sourceUserId { sd.sourceUserId = notification.sourceUserId; changed = true }
        return changed
    }

    private func updateSDPostIfChanged(_ sd: SDTownHallPost, with post: TownHallPost) -> Bool {
        var changed = false
        if sd.title != post.title { sd.title = post.title; changed = true }
        if sd.content != post.content { sd.content = post.content; changed = true }
        if sd.imageUrl != post.imageUrl { sd.imageUrl = post.imageUrl; changed = true }
        if sd.pinned != (post.pinned ?? false) { sd.pinned = post.pinned ?? false; changed = true }
        if sd.type != post.type?.rawValue { sd.type = post.type?.rawValue; changed = true }
        if sd.reviewId != post.reviewId { sd.reviewId = post.reviewId; changed = true }
        if sd.hiddenAt != post.hiddenAt { sd.hiddenAt = post.hiddenAt; changed = true }
        if sd.hiddenBy != post.hiddenBy { sd.hiddenBy = post.hiddenBy; changed = true }
        if sd.hiddenReason != post.hiddenReason { sd.hiddenReason = post.hiddenReason; changed = true }
        if sd.createdAt != post.createdAt { sd.createdAt = post.createdAt; changed = true }
        if sd.updatedAt != post.updatedAt { sd.updatedAt = post.updatedAt; changed = true }
        if sd.authorName != post.author?.name { sd.authorName = post.author?.name; changed = true }
        if sd.authorAvatarUrl != post.author?.avatarUrl { sd.authorAvatarUrl = post.author?.avatarUrl; changed = true }
        if sd.commentCount != post.commentCount { sd.commentCount = post.commentCount; changed = true }
        return changed
    }

    private func updateSDCommentIfChanged(_ sd: SDTownHallComment, with comment: TownHallComment) -> Bool {
        var changed = false
        if sd.postId != comment.postId { sd.postId = comment.postId; changed = true }
        if sd.userId != comment.userId { sd.userId = comment.userId; changed = true }
        if sd.parentCommentId != comment.parentCommentId { sd.parentCommentId = comment.parentCommentId; changed = true }
        if sd.content != comment.content { sd.content = comment.content; changed = true }
        if sd.hiddenAt != comment.hiddenAt { sd.hiddenAt = comment.hiddenAt; changed = true }
        if sd.hiddenBy != comment.hiddenBy { sd.hiddenBy = comment.hiddenBy; changed = true }
        if sd.hiddenReason != comment.hiddenReason { sd.hiddenReason = comment.hiddenReason; changed = true }
        if sd.createdAt != comment.createdAt { sd.createdAt = comment.createdAt; changed = true }
        if sd.updatedAt != comment.updatedAt { sd.updatedAt = comment.updatedAt; changed = true }
        if sd.authorName != comment.author?.name { sd.authorName = comment.author?.name; changed = true }
        if sd.authorAvatarUrl != comment.author?.avatarUrl { sd.authorAvatarUrl = comment.author?.avatarUrl; changed = true }
        return changed
    }

    // MARK: - Change-detection sync methods

    /// Full reconciliation with change detection. Only saves if at least one record changed.
    /// Returns metrics for observability.
    func syncAllWithChangeDetection(
        rides: [Ride], favors: [Favor], notifications: [AppNotification]
    ) throws -> RefreshMetrics {
        let start = Date()
        var evaluated = 0, mutated = 0, inserted = 0, deleted = 0

        // --- Rides ---
        let allLocalRides = (try? modelContext.fetch(FetchDescriptor<SDRide>())) ?? []
        let existingRidesById = Dictionary(uniqueKeysWithValues: allLocalRides.map { ($0.id, $0) })
        let serverRideIds = Set(rides.map { $0.id })
        evaluated += rides.count

        for ride in rides {
            if let existing = existingRidesById[ride.id] {
                if updateSDRideIfChanged(existing, with: ride) { mutated += 1 }
            } else {
                let sdRide = SDRide(
                    id: ride.id, userId: ride.userId, type: ride.type,
                    date: ride.date, time: ride.time, timezone: ride.timezone,
                    pickup: ride.pickup, destination: ride.destination,
                    seats: ride.seats, notes: ride.notes, gift: ride.gift,
                    status: ride.status.rawValue, claimedBy: ride.claimedBy,
                    reviewed: ride.reviewed, reviewSkipped: ride.reviewSkipped,
                    reviewSkippedAt: ride.reviewSkippedAt,
                    estimatedCost: ride.estimatedCost, flightNormalized: ride.flightNormalized,
                    hiddenAt: ride.hiddenAt, hiddenBy: ride.hiddenBy, hiddenReason: ride.hiddenReason,
                    createdAt: ride.createdAt, updatedAt: ride.updatedAt,
                    posterName: ride.poster?.name, posterAvatarUrl: ride.poster?.avatarUrl,
                    claimerName: ride.claimer?.name, claimerAvatarUrl: ride.claimer?.avatarUrl,
                    participantIds: ride.participants?.map { $0.id } ?? [],
                    qaCount: ride.qaCount ?? 0
                )
                modelContext.insert(sdRide)
                inserted += 1
            }
        }
        for local in allLocalRides where !serverRideIds.contains(local.id) {
            modelContext.delete(local)
            deleted += 1
        }

        // --- Favors ---
        let allLocalFavors = (try? modelContext.fetch(FetchDescriptor<SDFavor>())) ?? []
        let existingFavorsById = Dictionary(uniqueKeysWithValues: allLocalFavors.map { ($0.id, $0) })
        let serverFavorIds = Set(favors.map { $0.id })
        evaluated += favors.count

        for favor in favors {
            if let existing = existingFavorsById[favor.id] {
                if updateSDFavorIfChanged(existing, with: favor) { mutated += 1 }
            } else {
                let sdFavor = SDFavor(
                    id: favor.id, userId: favor.userId,
                    title: favor.title, favorDescription: favor.description,
                    location: favor.location, duration: favor.duration.rawValue,
                    requirements: favor.requirements,
                    date: favor.date, time: favor.time, timezone: favor.timezone,
                    gift: favor.gift, status: favor.status.rawValue,
                    claimedBy: favor.claimedBy,
                    reviewed: favor.reviewed, reviewSkipped: favor.reviewSkipped,
                    reviewSkippedAt: favor.reviewSkippedAt,
                    hiddenAt: favor.hiddenAt, hiddenBy: favor.hiddenBy, hiddenReason: favor.hiddenReason,
                    createdAt: favor.createdAt, updatedAt: favor.updatedAt,
                    posterName: favor.poster?.name, posterAvatarUrl: favor.poster?.avatarUrl,
                    claimerName: favor.claimer?.name, claimerAvatarUrl: favor.claimer?.avatarUrl,
                    participantIds: favor.participants?.map { $0.id } ?? [],
                    qaCount: favor.qaCount ?? 0
                )
                modelContext.insert(sdFavor)
                inserted += 1
            }
        }
        for local in allLocalFavors where !serverFavorIds.contains(local.id) {
            modelContext.delete(local)
            deleted += 1
        }

        // --- Notifications ---
        let allLocalNotifs = (try? modelContext.fetch(FetchDescriptor<SDNotification>())) ?? []
        let existingNotifsById = Dictionary(uniqueKeysWithValues: allLocalNotifs.map { ($0.id, $0) })
        evaluated += notifications.count

        for notification in notifications {
            if let existing = existingNotifsById[notification.id] {
                if updateSDNotificationIfChanged(existing, with: notification) { mutated += 1 }
            } else {
                let sd = SDNotification(
                    id: notification.id, userId: notification.userId,
                    type: notification.type.rawValue,
                    title: notification.title, body: notification.body,
                    read: notification.read, pinned: notification.pinned,
                    createdAt: notification.createdAt,
                    rideId: notification.rideId, favorId: notification.favorId,
                    conversationId: notification.conversationId,
                    reviewId: notification.reviewId,
                    townHallPostId: notification.townHallPostId,
                    sourceUserId: notification.sourceUserId
                )
                modelContext.insert(sd)
                inserted += 1
            }
        }

        let didMutate = mutated > 0 || inserted > 0 || deleted > 0
        if didMutate { try modelContext.save() }

        return RefreshMetrics(
            recordsEvaluated: evaluated, recordsMutated: mutated,
            recordsInserted: inserted, recordsDeleted: deleted,
            savedToStore: didMutate,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    /// Targeted single-ride upsert with change detection.
    func upsertRideWithChangeDetection(_ ride: Ride) throws -> RefreshMetrics {
        let start = Date()
        let rideId = ride.id
        let descriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == rideId })
        let existing = try? modelContext.fetch(descriptor).first

        var mutated = 0, inserted = 0
        if let existing {
            if updateSDRideIfChanged(existing, with: ride) { mutated = 1 }
        } else {
            let sdRide = SDRide(
                id: ride.id, userId: ride.userId, type: ride.type,
                date: ride.date, time: ride.time, timezone: ride.timezone,
                pickup: ride.pickup, destination: ride.destination,
                seats: ride.seats, notes: ride.notes, gift: ride.gift,
                status: ride.status.rawValue, claimedBy: ride.claimedBy,
                reviewed: ride.reviewed, reviewSkipped: ride.reviewSkipped,
                reviewSkippedAt: ride.reviewSkippedAt,
                estimatedCost: ride.estimatedCost, flightNormalized: ride.flightNormalized,
                hiddenAt: ride.hiddenAt, hiddenBy: ride.hiddenBy, hiddenReason: ride.hiddenReason,
                createdAt: ride.createdAt, updatedAt: ride.updatedAt,
                posterName: ride.poster?.name, posterAvatarUrl: ride.poster?.avatarUrl,
                claimerName: ride.claimer?.name, claimerAvatarUrl: ride.claimer?.avatarUrl,
                participantIds: ride.participants?.map { $0.id } ?? [],
                qaCount: ride.qaCount ?? 0
            )
            modelContext.insert(sdRide)
            inserted = 1
        }

        let didMutate = mutated > 0 || inserted > 0
        if didMutate { try modelContext.save() }

        return RefreshMetrics(
            recordsEvaluated: 1, recordsMutated: mutated,
            recordsInserted: inserted, recordsDeleted: 0,
            savedToStore: didMutate,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    /// Targeted single-favor upsert with change detection.
    func upsertFavorWithChangeDetection(_ favor: Favor) throws -> RefreshMetrics {
        let start = Date()
        let favorId = favor.id
        let descriptor = FetchDescriptor<SDFavor>(predicate: #Predicate { $0.id == favorId })
        let existing = try? modelContext.fetch(descriptor).first

        var mutated = 0, inserted = 0
        if let existing {
            if updateSDFavorIfChanged(existing, with: favor) { mutated = 1 }
        } else {
            let sdFavor = SDFavor(
                id: favor.id, userId: favor.userId,
                title: favor.title, favorDescription: favor.description,
                location: favor.location, duration: favor.duration.rawValue,
                requirements: favor.requirements,
                date: favor.date, time: favor.time, timezone: favor.timezone,
                gift: favor.gift, status: favor.status.rawValue,
                claimedBy: favor.claimedBy,
                reviewed: favor.reviewed, reviewSkipped: favor.reviewSkipped,
                reviewSkippedAt: favor.reviewSkippedAt,
                hiddenAt: favor.hiddenAt, hiddenBy: favor.hiddenBy, hiddenReason: favor.hiddenReason,
                createdAt: favor.createdAt, updatedAt: favor.updatedAt,
                posterName: favor.poster?.name, posterAvatarUrl: favor.poster?.avatarUrl,
                claimerName: favor.claimer?.name, claimerAvatarUrl: favor.claimer?.avatarUrl,
                participantIds: favor.participants?.map { $0.id } ?? [],
                qaCount: favor.qaCount ?? 0
            )
            modelContext.insert(sdFavor)
            inserted = 1
        }

        let didMutate = mutated > 0 || inserted > 0
        if didMutate { try modelContext.save() }

        return RefreshMetrics(
            recordsEvaluated: 1, recordsMutated: mutated,
            recordsInserted: inserted, recordsDeleted: 0,
            savedToStore: didMutate,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    /// Full town hall posts reconciliation with change detection.
    func syncPostsWithChangeDetection(_ posts: [TownHallPost]) throws -> RefreshMetrics {
        let start = Date()
        var evaluated = 0, mutated = 0, inserted = 0, deleted = 0

        let allLocal = (try? modelContext.fetch(FetchDescriptor<SDTownHallPost>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let serverIds = Set(posts.map { $0.id })
        evaluated = posts.count

        for post in posts {
            if let existing = existingById[post.id] {
                if updateSDPostIfChanged(existing, with: post) { mutated += 1 }
            } else {
                let sdPost = SDTownHallPost(
                    id: post.id, userId: post.userId,
                    title: post.title, content: post.content,
                    imageUrl: post.imageUrl, pinned: post.pinned ?? false,
                    type: post.type?.rawValue, reviewId: post.reviewId,
                    hiddenAt: post.hiddenAt, hiddenBy: post.hiddenBy, hiddenReason: post.hiddenReason,
                    createdAt: post.createdAt, updatedAt: post.updatedAt,
                    authorName: post.author?.name, authorAvatarUrl: post.author?.avatarUrl,
                    commentCount: post.commentCount
                )
                modelContext.insert(sdPost)
                inserted += 1
            }
        }

        for local in allLocal where !serverIds.contains(local.id) {
            modelContext.delete(local)
            deleted += 1
        }

        let didMutate = mutated > 0 || inserted > 0 || deleted > 0
        if didMutate { try modelContext.save() }

        return RefreshMetrics(
            recordsEvaluated: evaluated, recordsMutated: mutated,
            recordsInserted: inserted, recordsDeleted: deleted,
            savedToStore: didMutate,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    /// Full town hall comments reconciliation with change detection.
    func syncCommentsWithChangeDetection(_ comments: [TownHallComment], forPostId postId: UUID) throws -> RefreshMetrics {
        let start = Date()
        var evaluated = 0, mutated = 0, inserted = 0, deleted = 0

        let fetchDescriptor = FetchDescriptor<SDTownHallComment>(predicate: #Predicate { $0.postId == postId })
        let allLocal = (try? modelContext.fetch(fetchDescriptor)) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        // Flatten nested comment structure
        let flatComments = flattenTownHallComments(comments)
        let serverIds = Set(flatComments.map { $0.id })
        evaluated = flatComments.count

        for comment in flatComments {
            if let existing = existingById[comment.id] {
                if updateSDCommentIfChanged(existing, with: comment) { mutated += 1 }
            } else {
                let sdComment = SDTownHallComment(
                    id: comment.id, postId: comment.postId, userId: comment.userId,
                    parentCommentId: comment.parentCommentId, content: comment.content,
                    hiddenAt: comment.hiddenAt, hiddenBy: comment.hiddenBy, hiddenReason: comment.hiddenReason,
                    createdAt: comment.createdAt, updatedAt: comment.updatedAt,
                    authorName: comment.author?.name, authorAvatarUrl: comment.author?.avatarUrl
                )
                modelContext.insert(sdComment)
                inserted += 1
            }
        }

        for local in allLocal where !serverIds.contains(local.id) {
            modelContext.delete(local)
            deleted += 1
        }

        let didMutate = mutated > 0 || inserted > 0 || deleted > 0
        if didMutate { try modelContext.save() }

        return RefreshMetrics(
            recordsEvaluated: evaluated, recordsMutated: mutated,
            recordsInserted: inserted, recordsDeleted: deleted,
            savedToStore: didMutate,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    /// Flatten nested TownHallComment structure for batch processing.
    private func flattenTownHallComments(_ comments: [TownHallComment]) -> [TownHallComment] {
        var result: [TownHallComment] = []
        for comment in comments {
            result.append(comment)
            if let replies = comment.replies {
                result.append(contentsOf: flattenTownHallComments(replies))
            }
        }
        return result
    }

    /// Targeted single-post upsert with change detection.
    func upsertPostWithChangeDetection(_ post: TownHallPost) throws -> RefreshMetrics {
        let start = Date()
        let postId = post.id
        let descriptor = FetchDescriptor<SDTownHallPost>(predicate: #Predicate { $0.id == postId })
        let existing = try? modelContext.fetch(descriptor).first

        var mutated = 0, inserted = 0
        if let existing {
            if updateSDPostIfChanged(existing, with: post) { mutated = 1 }
        } else {
            let sdPost = SDTownHallPost(
                id: post.id, userId: post.userId,
                title: post.title, content: post.content,
                imageUrl: post.imageUrl, pinned: post.pinned ?? false,
                type: post.type?.rawValue, reviewId: post.reviewId,
                hiddenAt: post.hiddenAt, hiddenBy: post.hiddenBy, hiddenReason: post.hiddenReason,
                createdAt: post.createdAt, updatedAt: post.updatedAt,
                authorName: post.author?.name, authorAvatarUrl: post.author?.avatarUrl,
                commentCount: post.commentCount
            )
            modelContext.insert(sdPost)
            inserted = 1
        }

        let didMutate = mutated > 0 || inserted > 0
        if didMutate { try modelContext.save() }

        return RefreshMetrics(
            recordsEvaluated: 1, recordsMutated: mutated,
            recordsInserted: inserted, recordsDeleted: 0,
            savedToStore: didMutate,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
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
