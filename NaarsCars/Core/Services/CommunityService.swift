//
//  CommunityService.swift
//  NaarsCars
//
//  Reads the signed-in user's community memberships
//

import Foundation
import Supabase

final class CommunityService: CommunityServiceProtocol {
    static let shared = CommunityService()

    private init() {}

    func fetchMyMemberships() async throws -> [CommunityMembership] {
        let response = try await SupabaseService.shared.client
            .rpc("get_my_memberships")
            .execute()
        return try DateDecoderFactory.makeSupabaseDecoder()
            .decode([CommunityMembership].self, from: response.data)
    }
}
