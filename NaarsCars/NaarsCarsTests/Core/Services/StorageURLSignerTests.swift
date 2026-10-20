//
//  StorageURLSignerTests.swift
//  NaarsCarsTests
//
//  Parsing, signing once per object, renewal, in-flight dedup, fallback, the cache bound,
//  reset, the sign route and the no-cache download session.
//

import XCTest
@testable import NaarsCars

/// Counts calls, can throw, and can hold every call until the gate opens.
actor StubStorageObjectSigning: StorageObjectSigning {
    private(set) var calls: [(bucket: String, path: String, expiresIn: Int)] = []
    private var shouldThrow = false
    private var isGated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var callCount: Int { calls.count }

    func setThrowing(_ value: Bool) { shouldThrow = value }
    func closeGate() { isGated = true }
    func openGate() {
        isGated = false
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    func signedURL(bucket: String, path: String, expiresIn: Int) async throws -> URL {
        calls.append((bucket, path, expiresIn))
        let number = calls.count
        if isGated {
            await withCheckedContinuation { waiters.append($0) }
        }
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return URL(string: "https://example.supabase.co/storage/v1/object/sign/\(bucket)/\(path)?token=t\(number)")!
    }
}

/// A clock tests move by hand.
final class StorageTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_791_000_000)

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}

final class StorageURLSignerTests: XCTestCase {
    private let host = "example.supabase.co"
    private let lifetime = 3600
    private let margin: TimeInterval = 300

    private func storedURL(_ bucket: String, _ path: String, query: String = "") -> URL {
        URL(string: "https://\(host)/storage/v1/object/public/\(bucket)/\(path)\(query)")!
    }

    private func makeSigner(_ stub: StubStorageObjectSigning, clock: StorageTestClock, maxEntries: Int = 500) -> StorageURLSigner {
        StorageURLSigner(signer: stub, expectedHost: host, now: { clock.now() },
                         lifetime: lifetime, renewMargin: margin, maxEntries: maxEntries)
    }

    // MARK: - Parse

    func testParse_MessageImage() {
        let reference = StoredObjectReference.parse(storedURL("message-images", "C0/A1.jpg"), expectedHost: host)
        XCTAssertEqual(reference, StoredObjectReference(bucket: "message-images", path: "C0/A1.jpg"))
    }

    func testParse_ReviewURLDropsTheCacheBustQuery() {
        let reference = StoredObjectReference.parse(storedURL("review-images", "R1.jpg", query: "?t=17"), expectedHost: host)
        XCTAssertEqual(reference?.bucket, "review-images")
        XCTAssertEqual(reference?.path, "R1.jpg")
    }

    func testParse_ForeignHostAndSignPathAreNotParsed() {
        let foreign = URL(string: "https://other.example.com/storage/v1/object/public/message-images/C0/A1.jpg")!
        XCTAssertNil(StoredObjectReference.parse(foreign, expectedHost: host))
        let signRoute = URL(string: "https://\(host)/storage/v1/object/sign/message-images/C0/A1.jpg?token=t")!
        XCTAssertNil(StoredObjectReference.parse(signRoute, expectedHost: host))
        let emptyPath = URL(string: "https://\(host)/storage/v1/object/public/message-images/")!
        XCTAssertNil(StoredObjectReference.parse(emptyPath, expectedHost: host))
        let bucketOnly = URL(string: "https://\(host)/storage/v1/object/public/message-images")!
        XCTAssertNil(StoredObjectReference.parse(bucketOnly, expectedHost: host))
    }

    // MARK: - Resolve

    func testResolve_AvatarsPassThroughUnsigned() async {
        let stub = StubStorageObjectSigning()
        let signer = makeSigner(stub, clock: StorageTestClock())
        let avatar = storedURL("avatars", "U1.jpg")
        let resolved = await signer.resolvedURL(for: avatar)
        XCTAssertEqual(resolved, avatar)
        let count = await stub.callCount
        XCTAssertEqual(count, 0)
    }

    func testResolve_ReturnsSignedURLWithoutChangingTheStoredValue() async {
        let stub = StubStorageObjectSigning()
        let signer = makeSigner(stub, clock: StorageTestClock())
        let stored = storedURL("message-images", "C0/A1.jpg")
        let before = stored.absoluteString
        let resolved = await signer.resolvedURL(for: stored)
        XCTAssertEqual(stored.absoluteString, before)
        XCTAssertNotEqual(resolved, stored)
        XCTAssertTrue(resolved.query?.contains("token=t1") ?? false)
        let calls = await stub.calls
        XCTAssertEqual(calls.first?.bucket, "message-images")
        XCTAssertEqual(calls.first?.path, "C0/A1.jpg")
        XCTAssertEqual(calls.first?.expiresIn, lifetime)
    }

    func testResolve_AudioMessagesAreSigned() async {
        let stub = StubStorageObjectSigning()
        let signer = makeSigner(stub, clock: StorageTestClock())
        let stored = storedURL("audio-messages", "C0/V1.m4a")
        let resolved = await signer.resolvedURL(for: stored)
        XCTAssertTrue(resolved.query?.contains("token=t1") ?? false)
        let calls = await stub.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.bucket, "audio-messages")
        XCTAssertEqual(calls.first?.path, "C0/V1.m4a")
    }

    func testResolve_SignsOncePerPathWithinTheLifetime() async {
        let stub = StubStorageObjectSigning()
        let clock = StorageTestClock()
        let signer = makeSigner(stub, clock: clock)
        let stored = storedURL("group-images", "C0/avatar_A.jpg")
        let first = await signer.resolvedURL(for: stored)
        clock.advance(10 * 60)
        let second = await signer.resolvedURL(for: stored)
        XCTAssertEqual(first, second)
        let count = await stub.callCount
        XCTAssertEqual(count, 1)
    }

    func testResolve_RenewsInsideTheRenewMargin() async {
        let stub = StubStorageObjectSigning()
        let clock = StorageTestClock()
        let signer = makeSigner(stub, clock: clock)
        let stored = storedURL("town-hall-images", "P1.jpg")
        _ = await signer.resolvedURL(for: stored)
        clock.advance(TimeInterval(lifetime) - margin + 1)
        let renewed = await signer.resolvedURL(for: stored)
        let count = await stub.callCount
        XCTAssertEqual(count, 2)
        XCTAssertTrue(renewed.query?.contains("token=t2") ?? false)
    }

    func testResolve_ConcurrentCallsForOnePathShareOneRequest() async throws {
        let stub = StubStorageObjectSigning()
        await stub.closeGate()
        let signer = makeSigner(stub, clock: StorageTestClock())
        let stored = storedURL("message-images", "C0/A1.jpg")

        let results = Task { () -> [URL] in
            await withTaskGroup(of: URL.self) { group in
                for _ in 0..<20 {
                    group.addTask { await signer.resolvedURL(for: stored) }
                }
                var collected: [URL] = []
                for await url in group { collected.append(url) }
                return collected
            }
        }

        // Wait until the first sign is held at the gate, give the others time to queue, then open it.
        let deadline = Date().addingTimeInterval(2)
        while await stub.callCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        await stub.openGate()

        let urls = await results.value
        XCTAssertEqual(urls.count, 20)
        XCTAssertTrue(urls.allSatisfy { $0.query?.contains("token=t1") ?? false })
        let count = await stub.callCount
        XCTAssertEqual(count, 1)
    }

    func testResolve_SignerFailureFallsBackToStoredURLAndRetriesNextTime() async {
        let stub = StubStorageObjectSigning()
        await stub.setThrowing(true)
        let signer = makeSigner(stub, clock: StorageTestClock())
        let stored = storedURL("message-images", "C0/A1.jpg")

        let fallback = await signer.resolvedURL(for: stored)
        XCTAssertEqual(fallback, stored)

        await stub.setThrowing(false)
        let signed = await signer.resolvedURL(for: stored)
        let count = await stub.callCount
        XCTAssertEqual(count, 2)
        XCTAssertNotEqual(signed, stored)
    }

    func testResolve_CacheIsBounded() async {
        let stub = StubStorageObjectSigning()
        let clock = StorageTestClock()
        let signer = makeSigner(stub, clock: clock, maxEntries: 2)
        let a = storedURL("message-images", "C0/A.jpg")
        let b = storedURL("message-images", "C0/B.jpg")
        let c = storedURL("message-images", "C0/C.jpg")

        _ = await signer.resolvedURL(for: a)
        clock.advance(1)
        _ = await signer.resolvedURL(for: b)
        clock.advance(1)
        _ = await signer.resolvedURL(for: c)   // evicts a (earliest expiry)
        var count = await stub.callCount
        XCTAssertEqual(count, 3)

        _ = await signer.resolvedURL(for: c)   // still cached
        count = await stub.callCount
        XCTAssertEqual(count, 3)

        _ = await signer.resolvedURL(for: a)   // signed again
        count = await stub.callCount
        XCTAssertEqual(count, 4)
    }

    func testReset_ForgetsEverySignedURL() async {
        let stub = StubStorageObjectSigning()
        let signer = makeSigner(stub, clock: StorageTestClock())
        let stored = storedURL("review-images", "R1.jpg", query: "?t=17")
        _ = await signer.resolvedURL(for: stored)
        await signer.reset()
        _ = await signer.resolvedURL(for: stored)
        let count = await stub.callCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Production signer and session

    func testSupabaseStorageSigner_PostsToTheSignRoute() async throws {
        CommunityServiceURLProtocol.reset()
        URLProtocol.registerClass(CommunityServiceURLProtocol.self)
        defer {
            CommunityServiceURLProtocol.reset()
            URLProtocol.unregisterClass(CommunityServiceURLProtocol.self)
        }
        CommunityServiceURLProtocol.requestHandler = { request in
            let body = #"{"signedURL":"/object/sign/message-images/C0/A1.jpg?token=t"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, Data(body.utf8))
        }

        let url = try await SupabaseStorageSigner().signedURL(bucket: "message-images", path: "C0/A1.jpg", expiresIn: 3600)

        let request = try XCTUnwrap(CommunityServiceURLProtocol.recorded.last)
        XCTAssertEqual(request.method, "POST")
        XCTAssertTrue(request.path.hasSuffix("/storage/v1/object/sign/message-images/C0/A1.jpg"), request.path)
        XCTAssertEqual(request.body?["expiresIn"] as? Int, 3600)
        XCTAssertTrue(url.query?.contains("token=t") ?? false)
    }

    func testSignedStorageDownloadSession_HasNoURLCache() {
        let configuration = URLSession.signedStorageDownload.configuration
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }
}
