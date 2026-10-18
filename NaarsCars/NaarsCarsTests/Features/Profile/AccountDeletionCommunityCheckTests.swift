//
//  AccountDeletionCommunityCheckTests.swift
//  NaarsCarsTests
//
//  Which communities the account-deletion warning names (decision A3)
//

import XCTest
@testable import NaarsCars

final class AccountDeletionCommunityCheckTests: XCTestCase {

    private let me = CommunityFixtures.userA
    private let otherUser = UUID(uuidString: "0B000000-0000-4000-8000-0000000000B2")!
    private let thirdUser = UUID(uuidString: "0C000000-0000-4000-8000-0000000000C3")!

    private enum FetchError: Error { case offline }

    /// Records every community whose members were fetched.
    private actor FetchLog {
        private(set) var ids: [UUID] = []
        func record(_ id: UUID) { ids.append(id) }
    }

    private func member(_ id: UUID, role: CommunityRole, status: MembershipStatus = .active) -> CommunityMember {
        CommunityMember(
            id: id,
            name: "Member",
            avatarUrl: nil,
            car: nil,
            role: role,
            status: status,
            joinedAt: Date(timeIntervalSince1970: 1_760_000_000),
            activatedAt: nil,
            heardAbout: nil,
            joinReason: nil,
            invitedByName: nil,
            removalReason: nil
        )
    }

    private func ownedCommunity(_ id: UUID = CommunityFixtures.communityB, name: String = "Bellevue", isDefault: Bool = false) -> CommunityMembership {
        CommunityFixtures.membership(id, name: name, role: .owner, isDefault: isDefault)
    }

    func testSoleOwnerWithOnlyMembersIsClosed() async {
        let community = ownedCommunity()
        let members = [member(me, role: .owner), member(otherUser, role: .member), member(thirdUser, role: .member)]

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: [community],
            fetchActiveMembers: { _ in members }
        )

        XCTAssertEqual(closed.map(\.communityId), [community.communityId])
    }

    func testSoleOwnerAloneIsClosed() async {
        let community = ownedCommunity()

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: [community],
            fetchActiveMembers: { _ in [self.member(self.me, role: .owner)] }
        )

        XCTAssertEqual(closed.map(\.communityId), [community.communityId])
    }

    func testOwnerWithAnAdminIsNotClosed() async {
        let members = [member(me, role: .owner), member(otherUser, role: .admin), member(thirdUser, role: .member)]

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: [ownedCommunity()],
            fetchActiveMembers: { _ in members }
        )

        XCTAssertTrue(closed.isEmpty)
    }

    func testOwnerWithACoOwnerIsNotClosed() async {
        let members = [member(me, role: .owner), member(otherUser, role: .owner)]

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: [ownedCommunity()],
            fetchActiveMembers: { _ in members }
        )

        XCTAssertTrue(closed.isEmpty)
    }

    func testDefaultCommunityIsNeverListed() async {
        let log = FetchLog()
        let seattle = ownedCommunity(CommunityFixtures.communityA, name: "Seattle", isDefault: true)

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: [seattle],
            fetchActiveMembers: { id in
                await log.record(id)
                return [self.member(self.me, role: .owner)]
            }
        )

        XCTAssertTrue(closed.isEmpty)
        let fetched = await log.ids
        XCTAssertTrue(fetched.isEmpty, "the default community is never archived while a member remains (A3 + INV-L1)")
    }

    func testMemberAndAdminMembershipsAreNotFetched() async {
        let log = FetchLog()
        let memberships = [
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Seattle", role: .member),
            CommunityFixtures.membership(CommunityFixtures.communityB, name: "Bellevue", role: .admin),
            CommunityFixtures.membership(CommunityFixtures.communityC, name: "Tacoma", status: .pending, role: .owner)
        ]

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: memberships,
            fetchActiveMembers: { id in
                await log.record(id)
                return []
            }
        )

        XCTAssertTrue(closed.isEmpty)
        let fetched = await log.ids
        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchFailureListsTheCommunity() async {
        let failing = ownedCommunity(CommunityFixtures.communityB, name: "Bellevue")
        let withAdmin = ownedCommunity(CommunityFixtures.communityC, name: "Tacoma")
        let adminMembers = [member(me, role: .owner), member(otherUser, role: .admin)]

        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: me,
            memberships: [failing, withAdmin],
            fetchActiveMembers: { id in
                if id == CommunityFixtures.communityB { throw FetchError.offline }
                return adminMembers
            }
        )

        XCTAssertEqual(closed.map(\.communityId), [failing.communityId])
    }
}
