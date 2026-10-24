//
//  ReportContentViewModelTests.swift
//  NaarsCars
//

import XCTest
@testable import NaarsCars

/// A community report goes through `report_community`, which reads `auth.uid()` itself, so it does
/// not stop at the cached-user-id guard that every other report type keeps.
@MainActor
final class ReportContentViewModelTests: XCTestCase {
    private var stub: StubCommunityService!
    private var viewModel: ReportContentViewModel!
    private var savedUserId: UUID?

    override func setUp() {
        super.setUp()
        savedUserId = AuthService.shared.currentUserId
        AuthService.shared.currentUserId = nil
        stub = StubCommunityService(result: .success([]))
        viewModel = ReportContentViewModel(authService: AuthService.shared, communityService: stub)
    }

    override func tearDown() {
        AuthService.shared.currentUserId = savedUserId
        viewModel = nil
        stub = nil
        super.tearDown()
    }

    func testSubmitCommunityReport_WorksWithoutCachedUserId() async {
        XCTAssertNil(AuthService.shared.currentUserId)

        let submitted = await viewModel.submitReport(
            context: .community(id: nil, code: "NC7K2PQ9XA", name: "Ballard"),
            type: .spam,
            description: ""
        )

        XCTAssertTrue(submitted)
        XCTAssertEqual(stub.reportCommunityCalls.count, 1)
        XCTAssertEqual(stub.reportCommunityCalls.first?.code, "NC7K2PQ9XA")
        XCTAssertNil(stub.reportCommunityCalls.first?.communityId)
        XCTAssertEqual(stub.reportCommunityCalls.first?.type, .spam)
        XCTAssertNil(stub.reportCommunityCalls.first?.description)
        XCTAssertNil(viewModel.submitError)
    }

    func testSubmitCommunityReport_DuplicateCountsAsSuccess() async {
        stub.reportCommunityResult = .success(CommunityReportResult(reportId: nil, duplicate: true))

        let submitted = await viewModel.submitReport(
            context: .community(id: CommunityFixtures.communityA, code: nil, name: "Ballard"),
            type: .scam,
            description: "Asks for money"
        )

        XCTAssertTrue(submitted)
        XCTAssertNil(viewModel.submitError)
        XCTAssertEqual(stub.reportCommunityCalls.first?.communityId, CommunityFixtures.communityA)
        XCTAssertNil(stub.reportCommunityCalls.first?.code)
        XCTAssertEqual(stub.reportCommunityCalls.first?.description, "Asks for money")
    }

    func testSubmitCommunityReport_RateLimitedShowsLocalizedMessage() async {
        stub.reportCommunityResult = .failure(
            CommunityRPCError(code: .rateLimited, serverMessage: "Too many reports, try again later")
        )

        let submitted = await viewModel.submitReport(
            context: .community(id: CommunityFixtures.communityA, code: nil, name: "Ballard"),
            type: .other,
            description: ""
        )

        XCTAssertFalse(submitted)
        XCTAssertEqual(viewModel.submitError, "community_error_rate_limited".localized)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testSubmitPostReport_StillRequiresCachedUserId() async {
        XCTAssertNil(AuthService.shared.currentUserId)

        let submitted = await viewModel.submitReport(
            context: .post(id: UUID(), authorId: UUID(), preview: "A post"),
            type: .spam,
            description: ""
        )

        XCTAssertFalse(submitted)
        XCTAssertTrue(stub.reportCommunityCalls.isEmpty)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    /// The sheet's second footer line ("the community's admins see the report") is shown for every
    /// report that can carry a community. A community report goes to platform moderators only
    /// (`report_community`), so it must not claim that community admins see it.
    func testReachesCommunityAdmins_AllButCommunityReports() {
        let author = UUID()
        let reaching: [ReportContext] = [
            .post(id: UUID(), authorId: author, preview: "A post"),
            .comment(id: UUID(), authorId: author, preview: "A comment"),
            .ride(id: UUID(), authorId: author, preview: "A ride"),
            .favor(id: UUID(), authorId: author, preview: "A favor"),
            .user(id: UUID(), name: "Someone"),
            .review(id: UUID(), authorId: author, preview: "A review")
        ]
        for context in reaching {
            XCTAssertTrue(context.reachesCommunityAdmins, "\(context)")
        }
        XCTAssertFalse(ReportContext.community(id: UUID(), code: nil, name: "A community").reachesCommunityAdmins)
        XCTAssertFalse(ReportContext.community(id: nil, code: "ABC123", name: "A community").reachesCommunityAdmins)
    }
}
