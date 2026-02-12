//
//  ProfileServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol ProfileServiceProtocol: AnyObject {
    func fetchProfile(userId: UUID) async throws -> Profile
    func fetchProfiles(userIds: [UUID]) async throws -> [Profile]
    func fetchReviews(forUserId userId: UUID) async throws -> [Review]
    func calculateAverageRating(userId: UUID) async throws -> Double?
    func fetchFulfilledCount(userId: UUID) async throws -> Int
    func uploadAvatar(imageData: Data, userId: UUID) async throws -> String
    func updateProfile(
        userId: UUID,
        name: String?,
        phoneNumber: String?,
        car: String?,
        avatarUrl: String?,
        shouldUpdateAvatar: Bool
    ) async throws
}
