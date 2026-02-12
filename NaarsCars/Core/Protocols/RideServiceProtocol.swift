//
//  RideServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol RideServiceProtocol: AnyObject {
    func fetchRides(status: RideStatus?, userId: UUID?, claimedBy: UUID?) async throws -> [Ride]
    func fetchRide(id: UUID) async throws -> Ride
    func createRide(
        userId: UUID,
        date: Date,
        time: String,
        pickup: String,
        destination: String,
        seats: Int,
        notes: String?,
        gift: String?
    ) async throws -> Ride
    func addRideParticipants(rideId: UUID, userIds: [UUID], addedBy: UUID) async throws
    func fetchQA(requestId: UUID, requestType: String) async throws -> [RequestQA]
    func postQuestion(requestId: UUID, requestType: String, userId: UUID, question: String) async throws -> RequestQA
    func deleteRide(id: UUID) async throws
}
