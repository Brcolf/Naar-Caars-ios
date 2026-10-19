//
//  CommunityReportsViewModelTests.swift
//  NaarsCarsTests
//
//  Community reports: the action table that mirrors moderate_community_content, the localized
//  report type, the inline not-admin state, one action at a time, and a hide that sticks when
//  the follow-up reload fails
//

import XCTest
@testable import NaarsCars

@MainActor
final class CommunityReportsViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let authorId = UUID(uuidString: "DDDDDDDD-0000-4000-8000-000000000004")!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "CommunityReportsViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func report(
        _ id: String = "3E000000-0000-4000-8000-000000000001",
        targetType: String = "town_hall_post",
        reportType: String = "spam",
        status: String = "pending",
        contentHidden: Bool = false,
        canRestore: Bool = false,
        platformHandled: Bool = false
    ) -> CommunityReport {
        let isPerson = targetType == "user"
        return CommunityReport(
            reportId: UUID(uuidString: id)!,
            targetType: targetType,
            reportedUserId: isPerson ? self.authorId : nil,
            reportedUserName: isPerson ? "Dana Rivera" : nil,
            authorId: isPerson ? nil : self.authorId,
            authorName: isPerson ? nil : "Dana Rivera",
            reportedPostId: targetType == "town_hall_post" ? UUID(uuidString: "4E000000-0000-4000-8000-000000000001") : nil,
            reportedCommentId: nil, reportedRideId: nil, reportedFavorId: nil,
            townHallPostId: nil,
            reportType: reportType,
            description: "Posted three times",
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_790_100_000),
            reviewedAt: nil,
            contentPreview: "Selling a couch",
            contentHidden: contentHidden,
            reportCount: 1,
            canRestore: canRestore,
            platformHandled: platformHandled
        )
    }

    private func makeContext(role: CommunityRole) async -> (CommunityContext, StubCommunityService) {
        let stub = StubCommunityService(result: .success([
            CommunityFixtures.membership(CommunityFixtures.communityA, name: "Community A", role: role)
        ]))
        let context = CommunityContext(service: stub, defaults: defaults, platformAdminProvider: { false })
        context.restore(for: CommunityFixtures.userA)
        await context.refreshMemberships()
        return (context, stub)
    }

    private func makeViewModel(context: CommunityContext, admin: StubAdminService) -> CommunityReportsViewModel {
        CommunityReportsViewModel(communityId: CommunityFixtures.communityA, adminService: admin, communityContext: context)
    }

    // MARK: - Action table

    func testAvailableActions_MatchTheReportState() {
        XCTAssertEqual(CommunityReportActions.available(for: report()), [.hide, .dismiss])
        XCTAssertEqual(
            CommunityReportActions.available(for: report(contentHidden: true, canRestore: true)),
            [.restore, .dismiss]
        )
        XCTAssertEqual(
            CommunityReportActions.available(for: report(status: "action_taken", contentHidden: true, canRestore: true)),
            [.restore]
        )
        XCTAssertEqual(CommunityReportActions.available(for: report(status: "dismissed")), [.hide])
        XCTAssertEqual(CommunityReportActions.available(for: report(targetType: "user")), [.dismiss])
        XCTAssertEqual(CommunityReportActions.available(for: report(targetType: "user", status: "dismissed")), [])
    }

    func testAvailableActions_PlatformHandledAndPlatformHiddenOfferNothingTheServerRefuses() {
        XCTAssertEqual(
            CommunityReportActions.available(
                for: report(status: "action_taken", contentHidden: true, canRestore: false, platformHandled: true)
            ),
            []
        )
        XCTAssertEqual(
            CommunityReportActions.available(for: report(status: "dismissed", platformHandled: true)),
            []
        )
        // The 3-reporter auto-hide on a report still pending here: dismiss only, never hide or restore.
        XCTAssertEqual(
            CommunityReportActions.available(for: report(contentHidden: true, canRestore: false)),
            [.dismiss]
        )
        for status in ["pending", "action_taken", "dismissed"] {
            for canRestore in [false, true] {
                for platformHandled in [false, true] {
                    let actions = CommunityReportActions.available(
                        for: report(status: status, contentHidden: true, canRestore: canRestore, platformHandled: platformHandled)
                    )
                    XCTAssertFalse(actions.contains(.hide), "\(status) \(canRestore) \(platformHandled)")
                }
            }
        }
    }

    func testReportTypeLabel_UsesTheReportKeysAndFallsBackToOther() {
        XCTAssertEqual(report(reportType: "spam").reportTypeLabel, "messaging_report_spam".localized)
        XCTAssertEqual(
            report(reportType: "inappropriate_content").reportTypeLabel,
            "messaging_report_inappropriate_content".localized
        )
        XCTAssertEqual(report(reportType: "doxxing").reportTypeLabel, "messaging_report_other".localized)
        XCTAssertEqual(report(reportType: "").reportTypeLabel, "messaging_report_other".localized)
    }

    // MARK: - Load

    func testLoad_RefusalWithoutCodeShowsNotAdmin() async {
        let (context, _) = await makeContext(role: .admin)
        let admin = StubAdminService()
        admin.fetchCommunityReportsResult = .failure(
            CommunityRPCError(code: nil, serverMessage: "Only this community's admins can see its reports")
        )
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()

        XCTAssertEqual(admin.fetchCommunityReportsCalls.count, 1)
        XCTAssertEqual(vm.access, .notAdmin)
        XCTAssertNil(vm.loadError)
        XCTAssertNil(vm.actionErrorMessage)
        XCTAssertTrue(vm.reports.isEmpty)
    }

    func testLoad_FilterSendsStatus() async {
        let (context, _) = await makeContext(role: .admin)
        let admin = StubAdminService()
        let vm = makeViewModel(context: context, admin: admin)

        await vm.load()
        vm.filter = .all
        await vm.load()
        vm.filter = .resolved
        await vm.load()
        vm.filter = .dismissed
        await vm.load()

        XCTAssertEqual(admin.fetchCommunityReportsCalls.map(\.status), ["pending", nil, "action_taken", "dismissed"])
        XCTAssertTrue(admin.fetchCommunityReportsCalls.allSatisfy { $0.communityId == CommunityFixtures.communityA })
        XCTAssertEqual(vm.access, .allowed)
    }

    // MARK: - Moderate

    func testModerate_HideWithoutReasonSendsNothing() async {
        let (context, _) = await makeContext(role: .admin)
        let admin = StubAdminService()
        let pending = report()
        admin.fetchCommunityReportsResult = .success([pending])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        let ok = await vm.moderate(pending, action: .hide, reason: "  ")

        XCTAssertFalse(ok)
        XCTAssertTrue(admin.moderateCommunityContentCalls.isEmpty)
    }

    func testModerate_IgnoresSecondCallWhileActing() async {
        let (context, _) = await makeContext(role: .admin)
        let admin = StubAdminService()
        let first = report("3E000000-0000-4000-8000-000000000001")
        let second = report("3E000000-0000-4000-8000-000000000002")
        admin.fetchCommunityReportsResult = .success([first, second])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        var resume: CheckedContinuation<Void, Never>?
        admin.actionGate = { await withCheckedContinuation { resume = $0 } }
        let firstTask = Task { await vm.moderate(first, action: .hide, reason: "Spam") }
        for _ in 0..<200 where admin.moderateCommunityContentCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(admin.moderateCommunityContentCalls.count, 1)
        XCTAssertEqual(vm.actingOnReportId, first.id)

        let secondResult = await vm.moderate(second, action: .dismiss, reason: nil)
        XCTAssertFalse(secondResult)
        resume?.resume()
        let firstResult = await firstTask.value

        XCTAssertTrue(firstResult)
        XCTAssertEqual(admin.moderateCommunityContentCalls.count, 1)
        XCTAssertEqual(admin.moderateCommunityContentCalls[0].reportId, first.id)
        XCTAssertEqual(admin.moderateCommunityContentCalls[0].action, .hide)
        XCTAssertEqual(admin.moderateCommunityContentCalls[0].reason, "Spam")
        XCTAssertNil(vm.actingOnReportId)
    }

    func testModerate_UpdatesRowEvenWhenReloadFails() async {
        let (context, _) = await makeContext(role: .admin)
        let admin = StubAdminService()
        let pending = report()
        admin.fetchCommunityReportsResult = .success([pending])
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        admin.fetchCommunityReportsResult = .failure(URLError(.notConnectedToInternet))
        let fetchesBefore = admin.fetchCommunityReportsCalls.count
        let ok = await vm.moderate(pending, action: .hide, reason: "  Spam  ")

        XCTAssertTrue(ok)
        XCTAssertEqual(admin.moderateCommunityContentCalls.first?.reason, "Spam")
        XCTAssertEqual(admin.fetchCommunityReportsCalls.count, fetchesBefore + 1)
        XCTAssertEqual(vm.reports.count, 1)
        XCTAssertEqual(vm.reports.first?.status, "action_taken")
        XCTAssertEqual(vm.reports.first?.contentHidden, true)
        XCTAssertEqual(vm.reports.first?.canRestore, true)
        XCTAssertNil(vm.actionErrorMessage)
        XCTAssertNil(vm.loadError)
    }

    func testModerate_RefusalShowsActionFailedAndReloads() async {
        let (context, _) = await makeContext(role: .admin)
        let admin = StubAdminService()
        let pending = report()
        admin.fetchCommunityReportsResult = .success([pending])
        // `platform_handled` is a code this build does not know; it decodes as a refusal without one.
        admin.moderateCommunityContentResult = .failure(
            CommunityRPCError(code: nil, serverMessage: "Platform moderators have already handled this report")
        )
        let vm = makeViewModel(context: context, admin: admin)
        await vm.load()

        let handled = report(status: "action_taken", contentHidden: true, platformHandled: true)
        admin.fetchCommunityReportsResult = .success([handled])
        let fetchesBefore = admin.fetchCommunityReportsCalls.count
        let ok = await vm.moderate(pending, action: .dismiss, reason: nil)

        XCTAssertFalse(ok)
        XCTAssertEqual(admin.moderateCommunityContentCalls.count, 1)
        XCTAssertEqual(vm.actionErrorMessage, "community_reports_action_failed".localized)
        XCTAssertEqual(admin.fetchCommunityReportsCalls.count, fetchesBefore + 1)
        XCTAssertEqual(vm.reports.first?.platformHandled, true)
        XCTAssertEqual(CommunityReportActions.available(for: vm.reports[0]), [])
        XCTAssertNil(vm.actingOnReportId)
    }
}
