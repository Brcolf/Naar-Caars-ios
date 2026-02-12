//
//  ReviewServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol ReviewServiceProtocol: AnyObject {
    func createReview(
        requestType: String,
        requestId: UUID,
        fulfillerId: UUID,
        reviewerId: UUID,
        rating: Int,
        comment: String?,
        imageData: Data?
    ) async throws -> Review
    func skipReview(requestType: String, requestId: UUID) async throws
}
