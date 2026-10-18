//
//  CommunityServiceTests.swift
//  NaarsCarsTests
//
//  Stubbed tests for the community RPC envelope and every member-side CommunityService wrapper
//

import XCTest
@testable import NaarsCars

/// Records each request (method, path, query, JSON body) and answers with the installed handler.
final class CommunityServiceURLProtocol: URLProtocol {
    struct Recorded {
        let method: String
        let path: String
        let query: [String: String]
        let body: [String: Any]?
    }

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let lock = NSLock()
    private static var storedRequests: [Recorded] = []

    static var recorded: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        storedRequests = []
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Only intercept while a test has installed a handler.
        requestHandler != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request)
        guard let handler = Self.requestHandler else {
            let response = HTTPURLResponse(url: request.url ?? URL(string: "https://localhost")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func record(_ request: URLRequest) {
        var query: [String: String] = [:]
        if let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items { query[item.name] = item.value ?? "" }
        }
        let entry = Recorded(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            query: query,
            body: CommunityServiceTests.bodyJSON(of: request)
        )
        lock.lock(); defer { lock.unlock() }
        storedRequests.append(entry)
    }
}

final class CommunityServiceTests: XCTestCase {
    private var service: CommunityService { CommunityService.shared }
    private let fixedDate = Date(timeIntervalSince1970: 1_791_000_000)

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

    /// Reads `httpBody`, or drains `httpBodyStream` (URLProtocol usually receives the stream).
    static func bodyJSON(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data, !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func respond(with json: String) {
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://localhost")!,
                statusCode: 200,
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

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try CommunityRPC.decode(type, from: Data(json.utf8))
    }

    // MARK: - Envelope

    func testEnvelope_RefusalWithCodeThrowsTypedError() {
        XCTAssertThrowsError(try decode(CreatedCommunity.self, CommunityFixtures.ownedLimitRefusalJSON)) { error in
            guard let refusal = error as? CommunityRPCError else { return XCTFail("expected CommunityRPCError, got \(error)") }
            XCTAssertEqual(refusal.code, .ownedLimit)
            XCTAssertEqual(refusal.maxOwned, 3)
            XCTAssertEqual(refusal.ownedCount, 3)
            XCTAssertFalse(refusal.serverMessage.isEmpty)
        }
    }

    func testEnvelope_RefusalWithoutCodeHasNilCode() {
        XCTAssertThrowsError(try decode(CreatedCommunity.self, CommunityFixtures.refusalWithoutCodeJSON)) { error in
            guard let refusal = error as? CommunityRPCError else { return XCTFail("expected CommunityRPCError, got \(error)") }
            XCTAssertNil(refusal.code)
            XCTAssertEqual(refusal.localizedMessage, "community_error_generic".localized)
        }
    }

    func testEnvelope_UnknownCodeDecodesAsNil() {
        XCTAssertThrowsError(try CommunityRPC.decodeSuccess(from: Data(CommunityFixtures.unknownCodeRefusalJSON.utf8))) { error in
            guard let refusal = error as? CommunityRPCError else { return XCTFail("expected CommunityRPCError, got \(error)") }
            XCTAssertNil(refusal.code)
            XCTAssertEqual(refusal.serverMessage, "Something new")
        }
    }

    func testEnvelope_SuccessPayloadWithCodeKeyIsNotARefusal() throws {
        let invite = try decode(CommunityInvite.self, CommunityFixtures.inviteSuccessJSON)
        XCTAssertEqual(invite.code, "NC7K2PQ9XA")
        XCTAssertEqual(invite.inviteId, CommunityFixtures.inviteId)
        XCTAssertEqual(invite.maxUses, 1)
    }

    func testLocalizedMessage_EveryCodeHasAKey() {
        XCTAssertEqual(CommunityRefusalCode.allCases.count, 20)
        for code in CommunityRefusalCode.allCases {
            let error = CommunityRPCError(code: code, maxOwned: 3, ownedCount: 3, retryAfter: fixedDate)
            XCTAssertNotEqual(error.localizedMessage, "community_error_\(code.rawValue)", "missing string for \(code.rawValue)")
            XCTAssertFalse(error.localizedMessage.contains("%"), "unformatted placeholder for \(code.rawValue)")
        }
        XCTAssertNotEqual("community_error_generic".localized, "community_error_generic")
    }

    func testInviteCode_NormalizesFormattedPastedCode() {
        XCTAssertEqual(CommunityInviteCode.normalize("nc7k · 2pq9-xa "), "NC7K2PQ9XA")
        XCTAssertTrue(CommunityInviteCode.isWellFormed("NC7K2PQ9XA"))
        XCTAssertFalse(CommunityInviteCode.isWellFormed("NC0O1IL234"))
        XCTAssertFalse(CommunityInviteCode.isWellFormed("NC7K2PQ9X"))
    }

    // MARK: - Create and limits

    func testCreateCommunity_SendsNameDescriptionPolicy() async throws {
        respond(with: CommunityFixtures.createCommunitySuccessJSON)
        let created = try await service.createCommunity(name: "Ballard Neighbors", description: "Rides in Ballard", joinPolicy: .approve)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/create_community")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_name", "p_description", "p_join_policy"])
        XCTAssertEqual(request.body?["p_name"] as? String, "Ballard Neighbors")
        XCTAssertEqual(request.body?["p_join_policy"] as? String, "approve")
        XCTAssertEqual(created.communityId, CommunityFixtures.communityA)
    }

    func testCreateCommunity_OmitsNilDescription() async throws {
        respond(with: CommunityFixtures.createCommunitySuccessJSON)
        _ = try await service.createCommunity(name: "Ballard Neighbors", description: nil, joinPolicy: .invite)
        let request = try onlyRequest()
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_name", "p_join_policy"])
        XCTAssertEqual(request.body?["p_join_policy"] as? String, "invite")
    }

    func testFetchMyCommunityLimits_DecodesLatestRequest() async throws {
        respond(with: CommunityFixtures.limitsWithPendingRequestJSON)
        let limits = try await service.fetchMyCommunityLimits()
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_my_community_limits")
        XCTAssertEqual(limits.maxOwned, 3)
        XCTAssertEqual(limits.ownedCount, 3)
        XCTAssertFalse(limits.canCreate)
        XCTAssertNil(limits.nextCreateAt)
        XCTAssertEqual(limits.latestRequest?.status, .pending)
        XCTAssertEqual(limits.latestRequest?.requestedMax, 5)
        XCTAssertNil(limits.latestRequest?.decidedAt)
    }

    func testRequestOwnedCommunityLimit_SendsRequestedAndReason() async throws {
        respond(with: CommunityFixtures.limitRequestReceiptJSON)
        let receipt = try await service.requestOwnedCommunityLimit(requested: 5, reason: "I run three groups")
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/request_owned_community_limit")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_requested", "p_reason"])
        XCTAssertEqual(request.body?["p_requested"] as? Int, 5)
        XCTAssertEqual(request.body?["p_reason"] as? String, "I run three groups")
        XCTAssertEqual(receipt.requestId, UUID(uuidString: "2E000000-0000-4000-8000-000000000002"))
    }

    // MARK: - Invite codes

    func testCreateInvite_SendsExpiryAndOmitsNilMaxUses() async throws {
        respond(with: CommunityFixtures.inviteSuccessJSON)
        let invite = try await service.createInvite(communityId: CommunityFixtures.communityA, maxUses: nil, expiresAt: fixedDate)
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/create_community_invite")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_community_id", "p_expires_at"])
        XCTAssertEqual(invite.code, "NC7K2PQ9XA")
    }

    func testCreateInvite_AdminSendsUsesAndISO8601Expiry() async throws {
        respond(with: CommunityFixtures.inviteSuccessJSON)
        _ = try await service.createInvite(communityId: CommunityFixtures.communityA, maxUses: 25, expiresAt: fixedDate)
        let request = try onlyRequest()
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_community_id", "p_max_uses", "p_expires_at"])
        XCTAssertEqual(request.body?["p_max_uses"] as? Int, 25)
        XCTAssertEqual(request.body?["p_expires_at"] as? String, ISO8601DateFormatter().string(from: fixedDate))
        XCTAssertEqual((request.body?["p_community_id"] as? String)?.lowercased(), CommunityFixtures.communityA.uuidString.lowercased())
    }

    func testFetchLiveInvites_QueriesOwnLiveCodesAndDropsDeadOnes() async throws {
        respond(with: CommunityFixtures.liveInvitesJSON)
        let rows = try await service.fetchLiveInvites(communityId: CommunityFixtures.communityA, createdBy: CommunityFixtures.userA)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/rest/v1/community_invites")
        XCTAssertEqual(request.query["community_id"]?.lowercased(), "eq.\(CommunityFixtures.communityA.uuidString.lowercased())")
        XCTAssertEqual(request.query["created_by"]?.lowercased(), "eq.\(CommunityFixtures.userA.uuidString.lowercased())")
        XCTAssertEqual(request.query["revoked_at"]?.lowercased(), "is.null")
        XCTAssertEqual(rows.map(\.code), ["NC7K2PQ9XA"])
    }

    func testRevokeInvite_SendsInviteId() async throws {
        respond(with: #"{"success": true}"#)
        try await service.revokeInvite(inviteId: CommunityFixtures.inviteId)
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/revoke_community_invite")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_invite_id"])
    }

    func testValidateInvite_DecodesValidExpiredAndInvalid() async throws {
        respond(with: CommunityFixtures.validateValidJSON)
        let valid = try await service.validateInvite(code: "NC7K2PQ9XA")
        XCTAssertTrue(valid.valid)
        XCTAssertEqual(valid.requiresApproval, true)
        XCTAssertEqual(valid.communityName, "Ballard Neighbors")
        XCTAssertEqual(valid.alreadyMember, false)
        XCTAssertEqual(valid.memberCount, 12)

        respond(with: CommunityFixtures.validateExpiredJSON)
        let expired = try await service.validateInvite(code: "NC7K2PQ9XA")
        XCTAssertFalse(expired.valid)
        XCTAssertTrue(expired.expired)
        XCTAssertNil(expired.requiresApproval)

        respond(with: CommunityFixtures.validateInvalidJSON)
        let invalid = try await service.validateInvite(code: "NC7K2PQ9XA")
        XCTAssertFalse(invalid.valid)
        XCTAssertFalse(invalid.expired)
        XCTAssertNil(invalid.communityName)

        let first = try XCTUnwrap(CommunityServiceURLProtocol.recorded.first)
        XCTAssertEqual(first.path, "/rest/v1/rpc/validate_community_invite")
        XCTAssertEqual(Set(first.body?.keys ?? [:].keys), ["p_code"])
        XCTAssertEqual(first.body?["p_code"] as? String, "NC7K2PQ9XA")
    }

    func testRedeemInvite_SendsAnswersAndDecodesPending() async throws {
        respond(with: CommunityFixtures.redeemPendingJSON)
        let result = try await service.redeemInvite(code: "NC7K2PQ9XA", heardAbout: "A neighbour", joinReason: "I need rides")
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/redeem_community_invite")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_code", "p_heard_about", "p_join_reason"])
        XCTAssertEqual(request.body?["p_heard_about"] as? String, "A neighbour")
        XCTAssertEqual(result.communityId, CommunityFixtures.communityB)
        XCTAssertEqual(result.status, .pending)
    }

    func testRedeemInvite_RemovedThrowsRemoved() async {
        respond(with: CommunityFixtures.removedRefusalJSON)
        do {
            _ = try await service.redeemInvite(code: "NC7K2PQ9XA", heardAbout: nil, joinReason: nil)
            XCTFail("expected a refusal")
        } catch let error as CommunityRPCError {
            XCTAssertEqual(error.code, .removed)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let request = CommunityServiceURLProtocol.recorded.first
        XCTAssertEqual(Set(request?.body?.keys ?? [:].keys), ["p_code"], "nil answers are omitted")
    }

    // MARK: - Join, leave, mute, report

    func testFetchPublicCommunities_QueriesPublicOnly() async throws {
        respond(with: CommunityFixtures.publicCommunitiesJSON)
        let rows = try await service.fetchPublicCommunities()
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/rest/v1/communities")
        XCTAssertEqual(request.query["is_public"], "eq.true")
        XCTAssertEqual(rows.map(\.name), ["Ballard Neighbors", "Fremont Families"])
        XCTAssertEqual(rows.first?.joinPolicy, "approve")
        XCTAssertNil(rows.last?.description)
    }

    func testRequestToJoin_RecentlyRejectedCarriesRetryAfter() async {
        respond(with: CommunityFixtures.recentlyRejectedJSON)
        do {
            _ = try await service.requestToJoin(communityId: CommunityFixtures.communityB, heardAbout: nil, joinReason: nil)
            XCTFail("expected a refusal")
        } catch let error as CommunityRPCError {
            XCTAssertEqual(error.code, .recentlyRejected)
            XCTAssertNotNil(error.retryAfter)
            XCTAssertNotEqual(error.localizedMessage, "community_error_recently_rejected")
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let request = CommunityServiceURLProtocol.recorded.first
        XCTAssertEqual(request?.path, "/rest/v1/rpc/request_to_join_community")
        XCTAssertEqual(Set(request?.body?.keys ?? [:].keys), ["p_community_id"])
    }

    func testLeaveCommunity_DecodesCounts() async throws {
        respond(with: CommunityFixtures.leaveResultJSON)
        let result = try await service.leaveCommunity(communityId: CommunityFixtures.communityA)
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/leave_community")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_community_id"])
        XCTAssertEqual(result, LeaveResult(reopened: 2, removed: 1, cancelled: 3, archived: false))
    }

    func testSetCommunityMuted_PatchesWithExplicitNullMutedUntil() async throws {
        respond(with: #"[{"community_id": "AAAAAAAA-0000-4000-8000-000000000001"}]"#)
        try await service.setCommunityMuted(communityId: CommunityFixtures.communityA, muted: true)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.path, "/rest/v1/community_members")
        XCTAssertEqual(request.query["community_id"]?.lowercased(), "eq.\(CommunityFixtures.communityA.uuidString.lowercased())")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["notifications_muted", "muted_until"])
        XCTAssertEqual(request.body?["notifications_muted"] as? Bool, true)
        XCTAssertTrue(request.body?["muted_until"] is NSNull)
    }

    func testSetCommunityMuted_ZeroRowsThrows() async {
        respond(with: "[]")
        do {
            try await service.setCommunityMuted(communityId: CommunityFixtures.communityA, muted: false)
            XCTFail("expected membershipNotUpdated")
        } catch CommunityServiceError.membershipNotUpdated {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testReportCommunity_ByCodeOmitsCommunityId() async throws {
        respond(with: CommunityFixtures.reportSuccessJSON)
        let result = try await service.reportCommunity(communityId: nil, code: "NC7K2PQ9XA", type: .spam, description: nil)
        let request = try onlyRequest()
        XCTAssertEqual(request.path, "/rest/v1/rpc/report_community")
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_code", "p_report_type"])
        XCTAssertEqual(request.body?["p_report_type"] as? String, "spam")
        XCTAssertNotNil(result.reportId)
        XCTAssertFalse(result.duplicate)
    }

    func testReportCommunity_DuplicateIsSuccess() async throws {
        respond(with: CommunityFixtures.reportDuplicateJSON)
        let result = try await service.reportCommunity(communityId: CommunityFixtures.communityA, code: nil, type: .inappropriateContent, description: "Not neighbourly")
        let request = try onlyRequest()
        XCTAssertEqual(Set(request.body?.keys ?? [:].keys), ["p_community_id", "p_report_type", "p_description"])
        XCTAssertEqual(request.body?["p_report_type"] as? String, "inappropriate_content")
        XCTAssertTrue(result.duplicate)
        XCTAssertNil(result.reportId)
    }
}
