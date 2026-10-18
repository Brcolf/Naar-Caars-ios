//
//  CommunityServiceProtocol.swift
//  NaarsCars
//
//  Protocol abstraction for community membership reads
//

import Foundation

protocol CommunityServiceProtocol: AnyObject {
    /// Active and pending memberships of the signed-in user.
    func fetchMyMemberships() async throws -> [CommunityMembership]
}
