//
//  MessageAudioPlayerTests.swift
//  NaarsCarsTests
//
//  Voice notes download through the signed storage path and are cached under the stored URL.
//

import XCTest
@testable import NaarsCars

@MainActor
final class MessageAudioPlayerTests: XCTestCase {
    private var player: MessageAudioPlayer { MessageAudioPlayer.shared }
    private var resolver: StubStorageURLResolver!
    /// A fresh object path per run: the player's in-memory cache lives on the singleton.
    private var storedURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        CommunityServiceURLProtocol.reset()
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "audio/m4a"])!
            return (response, Data([0x00, 0x01, 0x02, 0x03]))
        }
        resolver = StubStorageURLResolver()
        player.urlResolver = resolver
        player.downloadSession = URLSession.makeSignedStorageDownloadSession(protocolClasses: [CommunityServiceURLProtocol.self])
        storedURL = URL(string: "https://example.supabase.co/storage/v1/object/public/audio-messages/C0/\(UUID().uuidString).m4a")!
    }

    override func tearDown() async throws {
        player.urlResolver = StorageURLSigner.shared
        player.downloadSession = .signedStorageDownload
        CommunityServiceURLProtocol.reset()
        resolver = nil
        storedURL = nil
        try await super.tearDown()
    }

    func testResolvePlayableURL_DownloadsSignedAndCachesUnderTheStoredURL() async throws {
        let fileURL = try await player.resolvePlayableUrl(for: storedURL)

        let request = try XCTUnwrap(CommunityServiceURLProtocol.recorded.last)
        XCTAssertEqual(request.query["token"], "t")
        XCTAssertTrue(request.path.hasPrefix("/storage/v1/object/public/audio-messages/C0/"))
        XCTAssertTrue(fileURL.isFileURL)
        XCTAssertFalse(fileURL.lastPathComponent.contains("token"), fileURL.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([0x00, 0x01, 0x02, 0x03]))

        let requestsAfterFirst = CommunityServiceURLProtocol.recorded.count
        let second = try await player.resolvePlayableUrl(for: storedURL)
        XCTAssertEqual(second, fileURL)
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, requestsAfterFirst, "a second call must not download")
        XCTAssertEqual(resolver.callCount, 1)

        let signedURL = await resolver.resolvedURL(for: storedURL)
        XCTAssertNil(URLCache.shared.cachedResponse(for: URLRequest(url: signedURL)))
        XCTAssertNil(player.downloadSession.configuration.urlCache)

        try? FileManager.default.removeItem(at: fileURL)
    }

    func testResolvePlayableURL_ErrorStatusIsNotCachedAndDownloadsAgain() async throws {
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, Data(#"{"error":"Bucket not found"}"#.utf8))
        }

        do {
            _ = try await player.resolvePlayableUrl(for: storedURL)
            XCTFail("a 400 answer must throw")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
        let requestsAfterFailure = CommunityServiceURLProtocol.recorded.count
        XCTAssertEqual(requestsAfterFailure, 1)

        // Nothing was cached: prefetch (errors dropped) downloads again and still caches nothing.
        await player.prefetch(storedURL)
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, requestsAfterFailure + 1)

        // Once storage answers 200, the next call downloads again and plays the real body.
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "audio/m4a"])!
            return (response, Data([0x0A, 0x0B]))
        }
        let fileURL = try await player.resolvePlayableUrl(for: storedURL)
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, requestsAfterFailure + 2)
        XCTAssertEqual(try Data(contentsOf: fileURL), Data([0x0A, 0x0B]))
        XCTAssertEqual(resolver.callCount, 3)

        try? FileManager.default.removeItem(at: fileURL)
    }
}
