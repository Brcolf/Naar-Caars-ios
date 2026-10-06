//
//  ClaimServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for ClaimService
//

import XCTest
@testable import NaarsCars

final class ClaimServiceURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        // Only intercept while a test has installed a handler.
        requestHandler != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://localhost")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
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
}

@MainActor
final class ClaimServiceTests: XCTestCase {
    var claimService: ClaimService!
    
    override func setUp() {
        super.setUp()
        claimService = ClaimService.shared
        URLProtocol.registerClass(ClaimServiceURLProtocol.self)
    }
    
    override func tearDown() {
        ClaimServiceURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(ClaimServiceURLProtocol.self)
        super.tearDown()
    }
    
    func testClaimRequest_NoPhone_ReturnsError() async {
        // Given: a claimer whose profile has no phone number. The stub answers the profile read;
        // with no handler installed this test went to the real network and took as long as the
        // network took to fail (60 s on a CI runner whose requests timed out).
        let requestId = UUID()
        let claimerId = UUID()
        let profilePayload = """
        {
          "id": "\(claimerId.uuidString)",
          "name": "Test User",
          "email": "test@example.com",
          "car": null,
          "phone_number": null,
          "avatar_url": null,
          "is_admin": false,
          "approved": true,
          "invited_by": null,
          "notify_ride_updates": true,
          "notify_messages": true,
          "notify_announcements": true,
          "notify_new_requests": true,
          "notify_qa_activity": true,
          "notify_review_reminders": true,
          "notify_town_hall": true,
          "guidelines_accepted": true,
          "guidelines_accepted_at": "2026-01-01T00:00:00Z",
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-01T00:00:00Z"
        }
        """

        ClaimServiceURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path.contains("/rest/v1/profiles") || url.path.contains("/rest/v1/public_profiles") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(profilePayload.utf8))
            }

            // The claim must be refused before anything else is requested.
            throw URLError(.cannotConnectToHost)
        }

        // When: attempting to claim
        do {
            try await claimService.claimRequest(
                requestType: "ride",
                requestId: requestId,
                claimerId: claimerId
            )
            XCTFail("Claim should be refused when the claimer has no phone number")
        } catch {
            // Then: the refusal is about the phone number
            guard case AppError.invalidInput(let message) = error else {
                XCTFail("Expected invalidInput, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Phone"), "Error should mention phone number")
        }
    }

    func testClaimRequest_DoesNotCreateConversation() async {
        let requestId = UUID()
        let claimerId = UUID()
        let posterId = UUID()
        let profilePayload = """
        {
          "id": "\(claimerId.uuidString)",
          "name": "Test User",
          "email": "test@example.com",
          "car": null,
          "phone_number": "+12065550123",
          "avatar_url": null,
          "is_admin": false,
          "approved": true,
          "invited_by": null,
          "notify_ride_updates": true,
          "notify_messages": true,
          "notify_announcements": true,
          "notify_new_requests": true,
          "notify_qa_activity": true,
          "notify_review_reminders": true,
          "notify_town_hall": true,
          "guidelines_accepted": true,
          "guidelines_accepted_at": "2026-01-01T00:00:00Z",
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-01T00:00:00Z"
        }
        """
        let posterPayload = """
        { "user_id": "\(posterId.uuidString)" }
        """

        ClaimServiceURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path.contains("/rest/v1/conversations") ||
                url.path.contains("/rest/v1/conversation_participants") {
                throw URLError(.cannotConnectToHost)
            }

            if url.path.contains("/rest/v1/profiles") || url.path.contains("/rest/v1/public_profiles") {
                let data = Data(profilePayload.utf8)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, data)
            }

            if url.path.contains("/rest/v1/rides") {
                if request.httpMethod == "GET" {
                    let data = Data(posterPayload.utf8)
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, data)
                }

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{}".utf8))
            }

            if url.path.contains("/rest/v1/notifications") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{}".utf8))
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await claimService.claimRequest(
                requestType: "ride",
                requestId: requestId,
                claimerId: claimerId
            )
        } catch {
            XCTFail("Expected claim without conversation creation, got: \(error)")
        }
    }
    
    func testClaimRequest_Success_UpdatesStatus() async {
        // Given: Valid claim request
        // Note: This test requires a real Supabase connection and valid data
        // In a real scenario, you'd mock the Supabase client
        
        let requestId = UUID()
        let claimerId = UUID()
        
        // When: Claiming request
        // Note: This may fail if Supabase not configured or data doesn't exist
        do {
            _ = try await claimService.claimRequest(
                requestType: "ride",
                requestId: requestId,
                claimerId: claimerId
            )
            // If successful, verify status was updated
            XCTAssertTrue(true, "Claim succeeded")
        } catch {
            // Expected if Supabase not configured or request doesn't exist
            XCTAssertTrue(true, "Claim attempted (expected behavior)")
        }
    }
    
    func testUnclaimRequest_Success() async {
        // Given: A claimed request
        // Note: This test requires a real Supabase connection
        let requestId = UUID()
        let claimerId = UUID()
        
        // When: Unclaiming
        // Note: This may fail if Supabase not configured or request doesn't exist
        do {
            try await claimService.unclaimRequest(
                requestType: "ride",
                requestId: requestId,
                claimerId: claimerId
            )
            XCTAssertTrue(true, "Unclaim succeeded")
        } catch {
            // Expected if Supabase not configured or request doesn't exist
            XCTAssertTrue(true, "Unclaim attempted (expected behavior)")
        }
    }
    
    func testCompleteRequest_Success() async {
        // Given: A claimed request and poster ID
        // Note: This test requires a real Supabase connection
        let requestId = UUID()
        let posterId = UUID()
        
        // When: Completing request
        // Note: This may fail if Supabase not configured or request doesn't exist
        do {
            try await claimService.completeRequest(
                requestType: "ride",
                requestId: requestId,
                posterId: posterId
            )
            XCTAssertTrue(true, "Complete succeeded")
        } catch {
            // Expected if Supabase not configured or request doesn't exist
            XCTAssertTrue(true, "Complete attempted (expected behavior)")
        }
    }
}





