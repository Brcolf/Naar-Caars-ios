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

    func testRequestsScope_ExcludingStorageRoundTripAndMalformedValues() {
        let a = CommunityFixtures.communityA, b = CommunityFixtures.communityB
        let scope = RequestsScope.excluding([b, a])
        XCTAssertEqual(scope.storageValue, "exclude:" + [a, b].map(\.uuidString).sorted().joined(separator: ","))
        XCTAssertEqual(RequestsScope(storageValue: scope.storageValue), scope)
        XCTAssertEqual(RequestsScope(storageValue: "exclude:"), .all)
        XCTAssertEqual(RequestsScope(storageValue: "exclude:garbage"), .all)
        XCTAssertEqual(RequestsScope(storageValue: "exclude:\(a.uuidString),garbage"), .excluding([a]))
        XCTAssertFalse(RequestsScope.excluding([a]).includes(a)); XCTAssertTrue(RequestsScope.excluding([a]).includes(b))
        XCTAssertTrue(RequestsScope.excluding([a]).includes(nil)); XCTAssertNil(RequestsScope.excluding([a]).communityId)
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

    func testJoinPolicy_ParsesServerValuesAndRejectsUnknown() {
        XCTAssertEqual(CommunityJoinPolicy(rawValue: "open"), .open)
        XCTAssertEqual(CommunityJoinPolicy(rawValue: "approve"), .approve)
        XCTAssertEqual(CommunityJoinPolicy(rawValue: "invite"), .invite)
        XCTAssertNil(CommunityJoinPolicy(rawValue: "public"))
    }

    func testJoinPolicy_ChipSubtitleRuleAndIcon() {   // English literals: the test locale is en
        XCTAssertEqual(CommunityJoinPolicy.approve.chipText, "Ask to join")
        XCTAssertEqual(CommunityJoinPolicy.invite.subtitleText, "Invite only")
        XCTAssertEqual(CommunityJoinPolicy.open.subtitleText, "Open community")
        XCTAssertEqual(CommunityJoinPolicy.approve.ruleSentence, "An admin approves every member. A helper's claim confirms at once.")
        XCTAssertEqual(CommunityJoinPolicy.open.ruleSentence,
                       "Anyone nearby can join. Helpers see only the area until a poster accepts them. No phone numbers are shown. Messaging opens when a poster accepts a helper.")
        XCTAssertEqual([CommunityJoinPolicy.open, .approve, .invite].map(\.systemImage), ["globe", "lock.fill", "key.fill"])
    }

    func testMonogramInitials() {
        XCTAssertEqual(CommunityMonogram.initials(for: "Ballard Neighbors"), "BN")
        XCTAssertEqual(CommunityMonogram.initials(for: "test community seattle"), "TC")
        XCTAssertEqual(CommunityMonogram.initials(for: "Solo"), "S")
        XCTAssertEqual(CommunityMonogram.initials(for: "   "), "?")
    }

    func testRequestTiles_AreOpenMineHelpingWithUnchangedIdentifiers() {
        XCTAssertEqual(RequestFilter.allCases.map(\.localizedKey), ["requests_tile_open", "requests_tile_mine", "requests_tile_helping"])
        XCTAssertEqual(RequestFilter.claimed.rawValue, "Claimed Requests")
    }

    // MARK: - Release 2 discovery (20261021_0021 block 7, 20261021_0022)

    func testPreview_DecodesAreaAndExampleFlag() throws {
        let preview = try CommunityRPC.decode(CommunityPreview.self, from: Data(CommunityFixtures.communityPreviewWithAreaJSON.utf8))
        XCTAssertEqual(preview.community.area, CommunityFixtures.seattleArea)
        XCTAssertEqual(preview.requests.map(\.isExample), [true, false])
    }

    func testPreview_Release1PayloadStillDecodes() throws {
        let preview = try CommunityRPC.decode(CommunityPreview.self, from: Data(CommunityFixtures.communityPreviewJSON.utf8))
        XCTAssertNil(preview.community.area)
        XCTAssertEqual(preview.requests.count, 2)
        XCTAssertTrue(preview.requests.allSatisfy { !$0.isExample })
    }

    func testRefusal_MergedCarriesTheSurvivor() {
        let json = """
        {"success": false, "error": "Community merged", "code": "merged",
         "merged_into_id": "\(CommunityFixtures.communityB.uuidString)", "merged_into_name": "Harbor Riders"}
        """
        XCTAssertThrowsError(try CommunityRPC.decode(CommunityPreview.self, from: Data(json.utf8))) { error in
            guard let refusal = error as? CommunityRPCError else { return XCTFail("expected CommunityRPCError, got \(error)") }
            XCTAssertEqual(refusal.code, .merged)
            XCTAssertEqual(refusal.mergedIntoId, CommunityFixtures.communityB)
            XCTAssertEqual(refusal.mergedIntoName, "Harbor Riders")
        }
    }

    func testSettings_DecodesTheServiceArea() throws {
        let row = """
        [{"id": "AAAAAAAA-0000-4000-8000-000000000001", "name": "Ballard Neighbors", "description": null,
          "join_policy": "approve", "members_can_invite": false, "is_public": true, "is_default": false,
          "timezone": "America/Los_Angeles", "area_name": %@, "area_center_lat": 47.6062,
          "area_center_lng": -122.3321, "area_radius_miles": 10}]
        """
        let decoder = DateDecoderFactory.makeSupabaseDecoder()
        let withArea = try decoder.decode([CommunitySettings].self, from: Data(row.replacingOccurrences(of: "%@", with: "\"Seattle\"").utf8))
        XCTAssertEqual(withArea.first?.area, CommunityFixtures.seattleArea)
        XCTAssertEqual(withArea.first?.name, "Ballard Neighbors")
        let withoutArea = try decoder.decode([CommunitySettings].self, from: Data(row.replacingOccurrences(of: "%@", with: "null").utf8))
        XCTAssertEqual(withoutArea.count, 1)
        XCTAssertNil(withoutArea.first?.area)
        let release1Row = try decoder.decode([CommunitySettings].self, from: Data(CommunityFixtures.communitySettingsRowsJSON.utf8))
        XCTAssertNil(release1Row.first?.area)
    }

    func testGeoPoint_RoundsToDecimals() {
        let point = GeoPoint(latitude: 47.60621, longitude: -122.33207).rounded(toDecimals: Constants.Community.searchCoordinateDecimals)
        XCTAssertEqual(point, GeoPoint(latitude: 47.606, longitude: -122.332))
    }

    func testServiceAreaMake_NeedsAllFourValues() {
        XCTAssertEqual(ServiceArea.make(name: "Seattle", latitude: 47.6062, longitude: -122.3321, radiusMiles: 10), CommunityFixtures.seattleArea)
        XCTAssertNil(ServiceArea.make(name: nil, latitude: 47.6062, longitude: -122.3321, radiusMiles: 10))
        XCTAssertNil(ServiceArea.make(name: "Seattle", latitude: nil, longitude: -122.3321, radiusMiles: 10))
        XCTAssertNil(ServiceArea.make(name: "Seattle", latitude: 47.6062, longitude: nil, radiusMiles: 10))
        XCTAssertNil(ServiceArea.make(name: "Seattle", latitude: 47.6062, longitude: -122.3321, radiusMiles: nil))
    }
}
