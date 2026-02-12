//
//  ClaimServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol ClaimServiceProtocol: AnyObject {
    func claimRequest(requestType: String, requestId: UUID, claimerId: UUID) async throws
    func unclaimRequest(requestType: String, requestId: UUID, claimerId: UUID) async throws
    func completeRequest(requestType: String, requestId: UUID, posterId: UUID) async throws
}
