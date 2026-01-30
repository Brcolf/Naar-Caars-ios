//
//  ConversationParticipantsViewModelTests.swift
//  NaarsCarsTests
//
//  Tests for participant loading fallbacks
//

import XCTest
@testable import NaarsCars

final class TestURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
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

private let _registerTestURLProtocol: Void = {
    URLProtocol.registerClass(TestURLProtocol.self)
    if let defaultClasses = URLSessionConfiguration.default.protocolClasses {
        URLSessionConfiguration.default.protocolClasses = [TestURLProtocol.self] + defaultClasses
    } else {
        URLSessionConfiguration.default.protocolClasses = [TestURLProtocol.self]
    }
}()

@MainActor
final class ConversationParticipantsViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = _registerTestURLProtocol
    }

    override func tearDown() {
        TestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoadParticipantsKeepsExistingWhenProfileFetchFails() async {
        let conversationId = UUID()
        let userId = UUID()
        let existingProfile = Profile(
            id: userId,
            name: "Test User",
            email: "test@example.com"
        )
        let viewModel = ConversationParticipantsViewModel(conversationId: conversationId)
        viewModel.participants = [existingProfile]

        TestURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path.contains("/rest/v1/conversation_participants") {
                let payload = """
                [{"user_id":"\(userId.uuidString)"}]
                """
                let data = Data(payload.utf8)
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, data)
            }

            if url.path.contains("/rest/v1/profiles") {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data())
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{}".utf8))
        }

        await viewModel.loadParticipants()

        XCTAssertEqual(viewModel.participants, [existingProfile])
    }
}

