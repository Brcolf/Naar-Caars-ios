//
//  BackgroundSyncActor.swift
//  NaarsCars
//
//  @ModelActor for off-MainActor SwiftData writes during dashboard sync.
//  SwiftUI @Query properties auto-update via persistent store observation.
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

    // MARK: - Internal sync logic

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
