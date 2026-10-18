//
//  CommunityPayloadDecodingTests.swift
//  NaarsCars
//
//  Decoding tests for get_my_memberships rows and RequestsScope
//

import XCTest
@testable import NaarsCars

final class CommunityPayloadDecodingTests: XCTestCase {
    func testMyMembershipsRowsDecode() throws {
        let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityMembership].self, from: Data(CommunityFixtures.myMembershipsJSON.utf8))
        XCTAssertEqual(rows.map(\.communityId), [CommunityFixtures.communityA, CommunityFixtures.communityB])
        XCTAssertEqual(rows[1].role, .admin)
        XCTAssertTrue(rows[1].isPrimary)
        XCTAssertEqual(rows[1].pendingCount, 2)
        XCTAssertNil(rows[0].pendingCount)
        XCTAssertEqual(rows[0].status, .active)
    }

    func testMembershipRequiresApprovalFollowsTheServerJoinPolicy() throws {
        let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityMembership].self, from: Data(CommunityFixtures.myMembershipsJSON.utf8))
        XCTAssertFalse(rows[0].requiresApproval)
        XCTAssertTrue(rows[1].requiresApproval)
    }

    func testRequestsScopeStorageRoundTripAndIncludes() {
        XCTAssertEqual(RequestsScope(storageValue: RequestsScope.community(CommunityFixtures.communityA).storageValue), .community(CommunityFixtures.communityA))
        XCTAssertEqual(RequestsScope(storageValue: "garbage"), .all)
        XCTAssertTrue(RequestsScope.community(CommunityFixtures.communityA).includes(nil))
        XCTAssertFalse(RequestsScope.community(CommunityFixtures.communityA).includes(CommunityFixtures.communityB))
    }

    func testMembershipWithUnknownRoleAndStatusDecodesTolerantly() throws {
        let rows = try DateDecoderFactory.makeSupabaseDecoder().decode([CommunityMembership].self, from: Data(CommunityFixtures.myMembershipsUnknownEnumsJSON.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].role, .member)
        XCTAssertEqual(rows[0].status, .pending)
    }

    func testCommunityLeaderboardParamsEncodeTheRPCKeys() throws {
        let data = try JSONEncoder().encode(CommunityLeaderboardParams(p_community_id: CommunityFixtures.communityA.uuidString, start_date: "2026-10-01", end_date: "2026-10-17"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(Set(object.keys), ["p_community_id", "start_date", "end_date"])
        XCTAssertEqual(object["p_community_id"], CommunityFixtures.communityA.uuidString)
    }

    func testCommunityLeaderboardRowDecodesAsLeaderboardEntry() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([LeaderboardEntry].self, from: Data(CommunityFixtures.communityLeaderboardRowsJSON.utf8))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].userId, UUID(uuidString: "DDDDDDDD-0000-4000-8000-000000000004"))
        XCTAssertEqual(entries[0].name, "Sam Neighbor")
        XCTAssertEqual(entries[0].xp, 120)
        XCTAssertEqual(entries[0].badges, [.roadWarrior])
    }

    func testProfileStatsDecode() throws {
        let stats = try JSONDecoder().decode(ProfileStats.self, from: Data(CommunityFixtures.profileStatsJSON.utf8))
        XCTAssertEqual(stats, ProfileStats(averageRating: 4.5, reviewCount: 3, fulfilledCount: 7))
    }

    func testProfileStatsEmptyObjectDecodesAsNothingVisible() throws {
        let stats = try JSONDecoder().decode(ProfileStats.self, from: Data(CommunityFixtures.profileStatsEmptyJSON.utf8))
        XCTAssertEqual(stats, ProfileStats(averageRating: nil, reviewCount: 0, fulfilledCount: 0))
    }

    func testSearchCommunityMembersRowsDecodeAsProfiles() throws {
        let profiles = try DateDecoderFactory.makeSupabaseDecoder().decode([Profile].self, from: Data(CommunityFixtures.searchMemberRowsJSON.utf8))
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].id, UUID(uuidString: "DDDDDDDD-0000-4000-8000-000000000004"))
        XCTAssertEqual(profiles[0].name, "Sam Neighbor")
    }
}
