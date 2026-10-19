//
//  AdminServiceTests.swift
//  NaarsCarsTests
//
//  Stubbed tests for every AdminService method that takes a community: figures, announcements,
//  community reports and community moderation (supabase/migrations/20261018_0001, 20261018_0002)
//

import XCTest
@testable import NaarsCars

final class AdminServiceTests: XCTestCase {
    private var service: AdminServiceProtocol { AdminService.shared }

    override func setUp() {
        super.setUp()
        CommunityServiceURLProtocol.reset()
        URLProtocol.registerClass(CommunityServiceURLProtocol.self)
    }

    override func tearDown() {
        CommunityServiceURLProtocol.reset()
        URLProtocol.unregisterClass(CommunityServiceURLProtocol.self)
        super.tearDown()
    }

    // MARK: - Helpers

    private func respond(with json: String, status: Int = 200) {
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://localhost")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    private func onlyRequest(file: StaticString = #filePath, line: UInt = #line) throws -> CommunityServiceURLProtocol.Recorded {
        let all = CommunityServiceURLProtocol.recorded
        XCTAssertEqual(all.count, 1, "expected exactly one request", file: file, line: line)
        return try XCTUnwrap(all.first, file: file, line: line)
    }

    private func keys(_ request: CommunityServiceURLProtocol.Recorded) -> Set<String> {
        Set(request.body?.keys ?? [:].keys)
    }

    private func uuidString(_ value: Any?) -> String? {
        (value as? String)?.lowercased()
    }

    // MARK: - Figures

    func testFetchDashboardStats_AllCommunitiesOmitsCommunityId() async throws {
        respond(with: CommunityFixtures.communityStatsJSON)
        let stats = try await service.fetchDashboardStats(communityId: nil)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_stats")
        XCTAssertEqual(keys(request), [])
        XCTAssertEqual(stats.fulfilledCount, 3)
        XCTAssertEqual(stats.totalSavings, 12.5, accuracy: 0.001)
        XCTAssertEqual(stats.activeRidesCount, 2)
    }

    func testFetchDashboardStats_CommunitySendsCommunityId() async throws {
        respond(with: CommunityFixtures.communityStatsJSON)
        _ = try await service.fetchDashboardStats(communityId: CommunityFixtures.communityA)
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_stats")
        XCTAssertEqual(keys(request), ["p_community_id"])
        XCTAssertEqual(uuidString(request.body?["p_community_id"]), CommunityFixtures.communityA.uuidString.lowercased())
    }

    func testFetchDashboardStats_RefusalThrowsCommunityRPCError() async {
        respond(with: CommunityFixtures.statsRefusalJSON)
        do {
            _ = try await service.fetchDashboardStats(communityId: CommunityFixtures.communityA)
            XCTFail("expected a refusal")
        } catch let error as CommunityRPCError {
            XCTAssertNil(error.code)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFetchFulfilledBreakdown_SendsPeriodAndCountAndDecodesRows() async throws {
        respond(with: CommunityFixtures.fulfilledRowsJSON)
        let rows = try await service.fetchFulfilledBreakdown(communityId: CommunityFixtures.communityA, period: "week", count: 12)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_stats_fulfilled")
        XCTAssertEqual(keys(request), ["p_community_id", "p_period", "p_count"])
        XCTAssertEqual(request.body?["p_period"] as? String, "week")
        XCTAssertEqual(request.body?["p_count"] as? Int, 12)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].rideCount, 2)
        XCTAssertEqual(rows[0].favorCount, 1)
        XCTAssertEqual(rows[0].totalCount, 3)
        XCTAssertEqual(rows[1].totalCount, 4)
    }

    func testFetchSavingsBreakdown_AllCommunitiesOmitsCommunityId() async throws {
        respond(with: CommunityFixtures.savingsRowsJSON)
        let rows = try await service.fetchSavingsBreakdown(communityId: nil, period: "month", count: 12)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_stats_savings")
        XCTAssertEqual(keys(request), ["p_period", "p_count"])
        XCTAssertEqual(request.body?["p_period"] as? String, "month")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].totalSavings, 40.25, accuracy: 0.001)
        XCTAssertEqual(rows[0].rideCount, 2)
    }

    func testFetchActiveRequests_DecodesRows() async throws {
        respond(with: CommunityFixtures.activeRequestRowsJSON)
        let rows = try await service.fetchActiveRequests(communityId: CommunityFixtures.communityA)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_stats_active_requests")
        XCTAssertEqual(keys(request), ["p_community_id"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows[0].isRide)
        XCTAssertEqual(rows[0].posterName, "Sam Neighbor")
        XCTAssertFalse(rows[1].isRide)
        XCTAssertEqual(rows[1].claimedBy, CommunityFixtures.userA)
    }

    // MARK: - Announcements

    func testSendBroadcast_SendsCommunityTitleBodyPinned() async throws {
        respond(with: "4")
        let told = try await service.sendBroadcast(
            communityId: CommunityFixtures.communityA,
            title: "Road closure",
            message: "Market St is closed Saturday",
            pinToNotifications: true
        )
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/send_community_broadcast")
        XCTAssertEqual(keys(request), ["p_community_id", "p_title", "p_body", "p_pinned"])
        XCTAssertEqual(uuidString(request.body?["p_community_id"]), CommunityFixtures.communityA.uuidString.lowercased())
        XCTAssertEqual(request.body?["p_title"] as? String, "Road closure")
        XCTAssertEqual(request.body?["p_body"] as? String, "Market St is closed Saturday")
        XCTAssertEqual(request.body?["p_pinned"] as? Bool, true)
        XCTAssertEqual(told, 4)
    }

    func testSendBroadcast_P0001MapsToDailyLimit() async {
        respond(
            with: #"{"code":"P0001","message":"This community has already sent 3 announcements today","details":null,"hint":null}"#,
            status: 400
        )
        do {
            _ = try await service.sendBroadcast(communityId: CommunityFixtures.communityA, title: "T", message: "B", pinToNotifications: false)
            XCTFail("expected the daily limit")
        } catch let error as AdminServiceError {
            XCTAssertEqual(error, .broadcastDailyLimit)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testSendBroadcast_42501MapsToNotCommunityAdmin() async {
        respond(
            with: #"{"code":"42501","message":"Only admins of this community can send announcements","details":null,"hint":null}"#,
            status: 403
        )
        do {
            _ = try await service.sendBroadcast(communityId: CommunityFixtures.communityA, title: "T", message: "B", pinToNotifications: false)
            XCTFail("expected not-an-admin")
        } catch let error as AdminServiceError {
            XCTAssertEqual(error, .notCommunityAdmin)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: - Community reports

    func testFetchCommunityReports_SendsCommunityAndStatus() async throws {
        respond(with: CommunityFixtures.communityReportsJSON)
        let reports = try await service.fetchCommunityReports(communityId: CommunityFixtures.communityA, status: "pending")
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_reports")
        XCTAssertEqual(keys(request), ["p_community_id", "p_status"])
        XCTAssertEqual(request.body?["p_status"] as? String, "pending")
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].id, CommunityFixtures.reportA)
        XCTAssertEqual(reports[0].targetType, "town_hall_post")
        XCTAssertEqual(reports[0].authorName, "Sam Neighbor")
        XCTAssertEqual(reports[0].townHallPostId, CommunityFixtures.postA)
        XCTAssertEqual(reports[0].description, "Posted three times\nin one hour")
        XCTAssertTrue(reports[0].contentHidden)
        XCTAssertEqual(reports[0].reportCount, 2)
        XCTAssertTrue(reports[0].canRestore)
        XCTAssertFalse(reports[0].platformHandled)
        XCTAssertFalse(reports[0].isPersonReport)
        XCTAssertEqual(reports[1].id, CommunityFixtures.reportB)
        XCTAssertEqual(reports[1].reportedRideId, CommunityFixtures.rideA)
        XCTAssertTrue(reports[1].platformHandled)
        XCTAssertFalse(reports[1].canRestore)
        XCTAssertEqual(reports[1].reportCount, 1)
    }

    func testFetchCommunityReports_NilStatusIsOmitted() async throws {
        respond(with: CommunityFixtures.communityReportsJSON)
        _ = try await service.fetchCommunityReports(communityId: CommunityFixtures.communityA, status: nil)
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_community_reports")
        XCTAssertEqual(keys(request), ["p_community_id"])
    }

    func testFetchCommunityReports_RefusalWithoutCodeThrowsNilCode() async {
        respond(with: CommunityFixtures.reportsRefusalWithoutCodeJSON)
        do {
            _ = try await service.fetchCommunityReports(communityId: CommunityFixtures.communityA, status: nil)
            XCTFail("expected a refusal")
        } catch let error as CommunityRPCError {
            XCTAssertNil(error.code)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCommunityReport_HasNoReporterField() throws {
        let payload = try CommunityRPC.decode(CommunityReportsPayload.self, from: Data(CommunityFixtures.communityReportsJSON.utf8))
        XCTAssertEqual(payload.reports.count, 2)
        for report in payload.reports {
            let labels = Mirror(reflecting: report).children.compactMap { $0.label?.lowercased() }
            XCTAssertFalse(labels.isEmpty)
            XCTAssertFalse(labels.contains { $0.contains("reporter") }, "CommunityReport must not hold a reporter: \(labels)")
        }
    }

    // MARK: - Community moderation

    func testModerateCommunityContent_DismissOmitsNilReason() async throws {
        respond(with: CommunityFixtures.moderateSuccessJSON)
        try await service.moderateCommunityContent(reportId: CommunityFixtures.reportA, action: .dismiss, reason: nil)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/moderate_community_content")
        XCTAssertEqual(keys(request), ["p_report_id", "p_action"])
        XCTAssertEqual(uuidString(request.body?["p_report_id"]), CommunityFixtures.reportA.uuidString.lowercased())
        XCTAssertEqual(request.body?["p_action"] as? String, "dismiss")
    }

    func testModerateCommunityContent_HideSendsReason() async throws {
        respond(with: CommunityFixtures.moderateSuccessJSON)
        try await service.moderateCommunityContent(reportId: CommunityFixtures.reportA, action: .hide, reason: "Spam")
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/moderate_community_content")
        XCTAssertEqual(keys(request), ["p_report_id", "p_action", "p_reason"])
        XCTAssertEqual(request.body?["p_action"] as? String, "hide")
        XCTAssertEqual(request.body?["p_reason"] as? String, "Spam")
    }

    func testModerateCommunityContent_RefusalThrows() async {
        respond(with: #"{"success": false, "error": "This content is already hidden", "code": "already_hidden"}"#)
        do {
            try await service.moderateCommunityContent(reportId: CommunityFixtures.reportA, action: .hide, reason: "Spam")
            XCTFail("expected a refusal")
        } catch let error as CommunityRPCError {
            // A code this build does not know decodes as nil.
            XCTAssertNil(error.code)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
