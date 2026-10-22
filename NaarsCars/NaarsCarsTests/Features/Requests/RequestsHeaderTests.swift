//
//  RequestsHeaderTests.swift
//  NaarsCars
//
//  The Requests header rules: title, policy subtitle and whether the community chips show
//

import XCTest
@testable import NaarsCars

@MainActor
final class RequestsHeaderTests: XCTestCase {
    // English literals: the test locale is en.
    private let harbor = CommunityFixtures.membership(CommunityFixtures.communityA, name: "Harbor Riders", isPrimary: true, joinPolicy: "approve")
    private let fremont = CommunityFixtures.membership(CommunityFixtures.communityB, name: "Fremont Porch Club", joinPolicy: "invite")

    func testHeader_GuestIsRequests() {
        XCTAssertEqual(
            RequestsDashboardViewModel.header(scope: .all, activeMemberships: [harbor, fremont], isGuest: true),
            RequestsHeader(title: "Requests", subtitle: nil, showsCommunityChips: false)
        )
    }

    func testHeader_OneMembershipNamesItWithItsRule() {
        XCTAssertEqual(
            RequestsDashboardViewModel.header(scope: .all, activeMemberships: [harbor], isGuest: false),
            RequestsHeader(title: "Harbor Riders", subtitle: "Ask to join", showsCommunityChips: false)
        )
    }

    func testHeader_TwoMembershipsShowAllCommunitiesAndChips() {
        XCTAssertEqual(
            RequestsDashboardViewModel.header(scope: .all, activeMemberships: [harbor, fremont], isGuest: false),
            RequestsHeader(title: "All communities", subtitle: nil, showsCommunityChips: true)
        )
    }

    func testHeader_NarrowedShowsTheCommunityAndItsRule() {
        XCTAssertEqual(
            RequestsDashboardViewModel.header(scope: .community(CommunityFixtures.communityB), activeMemberships: [harbor, fremont], isGuest: false),
            RequestsHeader(title: "Fremont Porch Club", subtitle: "Invite only", showsCommunityChips: false)
        )
    }

    func testHeader_ExcludingKeepsAllCommunitiesAndChips() {
        XCTAssertEqual(
            RequestsDashboardViewModel.header(scope: .excluding([CommunityFixtures.communityA]), activeMemberships: [harbor, fremont], isGuest: false),
            RequestsHeader(title: "All communities", subtitle: nil, showsCommunityChips: true)
        )
    }
}
