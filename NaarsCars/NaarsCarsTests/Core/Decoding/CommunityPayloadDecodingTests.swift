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
}
