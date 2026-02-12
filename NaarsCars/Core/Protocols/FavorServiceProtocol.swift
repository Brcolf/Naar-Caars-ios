//
//  FavorServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol FavorServiceProtocol: AnyObject {
    func fetchFavors(status: FavorStatus?, userId: UUID?, claimedBy: UUID?) async throws -> [Favor]
    func fetchFavor(id: UUID) async throws -> Favor
    func createFavor(
        userId: UUID,
        title: String,
        description: String?,
        location: String,
        duration: FavorDuration,
        requirements: String?,
        date: Date,
        time: String?,
        gift: String?
    ) async throws -> Favor
    func addFavorParticipants(favorId: UUID, userIds: [UUID], addedBy: UUID) async throws
    func deleteFavor(id: UUID) async throws
}
