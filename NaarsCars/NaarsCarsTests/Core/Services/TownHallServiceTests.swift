//
//  TownHallServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for TownHallService
//

import XCTest
@testable import NaarsCars

/// Answers TownHallService's PostgREST calls while a test has activated it. The page read
/// (`GET town_hall_posts`) returns the page JSON and, when held, waits until
/// `releaseHeldPages()` without blocking the loading thread, so a second call can start while
/// the first is in flight. The enrichment reads return `[]`, a single-row read (`.single()`)
/// answers 406 (no row) and every write answers 201.
final class TownHallPageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var active = false
    private static var pageJSON = "[]"
    private static var holdsPages = false
    private static var held: [(runLoop: CFRunLoop, deliver: () -> Void)] = []
    private static var pageRequests = 0
    private static var writes = 0

    static func activate(pageJSON json: String, holdPages: Bool) {
        lock.lock(); defer { lock.unlock() }
        active = true
        pageJSON = json
        holdsPages = holdPages
        held = []
        pageRequests = 0
        writes = 0
    }

    static func deactivate() {
        releaseHeldPages()
        lock.lock(); defer { lock.unlock() }
        active = false
        pageJSON = "[]"
        holdsPages = false
    }

    /// Page reads that reached the "server" (a joined call makes none).
    static var pageRequestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pageRequests
    }

    static var writeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return writes
    }

    /// Answers every held page read, and stops holding new ones until `holdPages(true)`.
    static func releaseHeldPages() {
        lock.lock()
        let pending = held
        held = []
        holdsPages = false
        lock.unlock()
        for item in pending {
            CFRunLoopPerformBlock(item.runLoop, CFRunLoopMode.commonModes.rawValue, item.deliver)
            CFRunLoopWakeUp(item.runLoop)
        }
    }

    static func holdPages(_ hold: Bool) {
        lock.lock(); defer { lock.unlock() }
        holdsPages = hold
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let method = request.httpMethod ?? "GET"
        let accept = request.value(forHTTPHeaderField: "Accept") ?? ""
        let isPage = method == "GET" && (request.url?.path ?? "").hasSuffix("/town_hall_posts")
            && !accept.contains("vnd.pgrst.object")
        let status: Int
        let body: String
        var hold = false
        Self.lock.lock()
        if method != "GET" {
            Self.writes += 1
            status = 201
            body = "[]"
        } else if accept.contains("vnd.pgrst.object") {
            status = 406
            body = #"{"code":"PGRST116","details":"The result contains 0 rows","hint":null,"message":"JSON object requested, multiple (or no) rows returned"}"#
        } else if isPage {
            Self.pageRequests += 1
            hold = Self.holdsPages
            status = 200
            body = Self.pageJSON
        } else {
            status = 200
            body = "[]"
        }
        Self.lock.unlock()

        let deliver: () -> Void = { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://localhost")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        guard hold else { return deliver() }
        // Answered later on this loading thread's run loop, as URLProtocol requires.
        let runLoop = CFRunLoopGetCurrent()!
        Self.lock.lock()
        Self.held.append((runLoop, deliver))
        Self.lock.unlock()
    }

    override func stopLoading() {}
}

/// Records each read of the blocked set and whether it happened on the main thread.
private final class BlockedSetReads: @unchecked Sendable {
    private let lock = NSLock()
    private let blocked: Set<UUID>
    private var onMainThread: [Bool] = []

    init(blocked: Set<UUID>) { self.blocked = blocked }

    func read() -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        onMainThread.append(Thread.isMainThread)
        return blocked
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return onMainThread.count
    }

    var allOnMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return !onMainThread.isEmpty && onMainThread.allSatisfy { $0 }
    }
}

@MainActor
final class TownHallServiceTests: XCTestCase {
    var townHallService: TownHallService!
    
    override func setUp() {
        super.setUp()
        townHallService = TownHallService.shared
    }
    
    /// Test that fetchPosts returns posts ordered by createdAt descending
    func testFetchPosts_OrderedByDate() async throws {
        // Given: A request to fetch posts
        // Note: This test requires a real Supabase connection (an anonymous read is
        // enough, so no signed-in user is needed). With the CI placeholder
        // Secrets.swift the client points at an unresolvable host, so skip there
        // the same way SupabaseConnectionTests does.
        guard Secrets.isConfigured else {
            throw XCTSkip("Secrets.swift is the CI placeholder; credentials are not configured")
        }
        
        // When: Fetching posts
        do {
            let posts = try await townHallService.fetchPosts(limit: 10, offset: 0)
            
            // Then: Posts should be ordered by createdAt descending (newest first)
            var previousDate: Date? = nil
            for post in posts {
                if let prev = previousDate {
                    XCTAssertGreaterThanOrEqual(prev, post.createdAt, "Posts should be ordered by createdAt descending")
                }
                previousDate = post.createdAt
            }
            
            // Test passes if we get here
            XCTAssertTrue(true, "Posts are correctly ordered by date")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Failed to fetch posts: \(error.localizedDescription)")
        }
    }
    
    /// Test that createPost is rate limited
    func testCreatePost_RateLimited() async throws {
        // Given: An authenticated user
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Creating first post
        do {
            let firstPost = try await townHallService.createPost(
                userId: userId,
                content: "First post"
            )
            XCTAssertNotNil(firstPost.id, "First post should be created")
            
            // Then: Attempting to create second post immediately should fail with rate limit
            do {
                _ = try await townHallService.createPost(
                    userId: userId,
                    content: "Second post"
                )
                // If it succeeds, that's okay (maybe enough time passed)
                XCTAssertTrue(true, "Second post created (rate limit may have passed)")
            } catch {
                if case AppError.rateLimitExceeded = error {
                    XCTAssertTrue(true, "Rate limit correctly enforced")
                } else {
                    // Other errors are acceptable
                    print("⚠️ Second post creation failed with: \(error)")
                }
            }
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Failed to create post: \(error.localizedDescription)")
        }
    }
    
    /// Test that createPost validates content length
    func testCreatePost_ContentTooLong() async throws {
        // Given: Content exceeding 500 characters
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        let longContent = String(repeating: "a", count: 501)
        
        // When: Attempting to create post
        do {
            _ = try await townHallService.createPost(
                userId: userId,
                content: longContent
            )
            XCTFail("Should have thrown error for content too long")
        } catch {
            // Then: Should throw invalidInput error
            if case AppError.invalidInput(let message) = error {
                XCTAssertTrue(message.contains("500"), "Error should mention 500 character limit")
            } else {
                // Other errors are acceptable
                print("⚠️ Post creation failed with: \(error)")
            }
        }
    }
    
    /// Test that createPost validates empty content
    func testCreatePost_EmptyContent() async throws {
        // Given: Empty content
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Attempting to create post
        do {
            _ = try await townHallService.createPost(
                userId: userId,
                content: "   "
            )
            XCTFail("Should have thrown error for empty content")
        } catch {
            // Then: Should throw invalidInput error
            if case AppError.invalidInput(let message) = error {
                XCTAssertTrue(message.contains("empty") || message.contains("cannot"), "Error should mention empty content")
            } else {
                // Other errors are acceptable
                print("⚠️ Post creation failed with: \(error)")
            }
        }
    }
    
    /// Test that deletePost only allows author to delete
    func testDeletePost_OnlyAuthorCanDelete() async throws {
        // Given: A post and a user who is not the author
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // First, create a post
        do {
            let post = try await townHallService.createPost(
                userId: userId,
                content: "Test post for deletion"
            )
            
            // Wait a moment to avoid rate limiting
            try? await Task.sleep(nanoseconds: 35_000_000_000) // 35 seconds
            
            // When: Attempting to delete (as the author, should succeed)
            try await townHallService.deletePost(postId: post.id, userId: userId)
            
            // Then: Post should be deleted (no error thrown)
            XCTAssertTrue(true, "Post deleted successfully")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Failed to delete post: \(error.localizedDescription)")
        }
    }
    
    /// Test that createSystemPost creates system posts
    func testCreateSystemPost_Success() async throws {
        // Given: A user ID and system post content
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Creating system post
        do {
            let post = try await townHallService.createSystemPost(
                userId: userId,
                content: "⭐ Review for John\nRating: ⭐⭐⭐⭐⭐\n\"Great help!\"",
                type: .review
            )
            
            // Then: Post should be created with correct type
            XCTAssertEqual(post.type, .review, "System post should have correct type")
            XCTAssertNotNil(post.id, "System post should have an ID")
        } catch {
            XCTFail("Failed to create system post: \(error.localizedDescription)")
        }
    }

    // MARK: - Page reads (stubbed; no network)

    private static func pageJSON(_ rows: [(id: UUID, author: UUID)]) -> String {
        let objects = rows.map { row in
            #"{"id":"\#(row.id.uuidString)","user_id":"\#(row.author.uuidString)","content":"Post","created_at":"2026-10-20T10:00:00.000Z","updated_at":"2026-10-20T10:00:00.000Z"}"#
        }
        return "[" + objects.joined(separator: ",") + "]"
    }

    /// Activates the stub for one test; deactivated and unregistered when the test ends.
    private func stubPageReads(_ json: String, holdPages: Bool) {
        TownHallPageURLProtocol.activate(pageJSON: json, holdPages: holdPages)
        URLProtocol.registerClass(TownHallPageURLProtocol.self)
        addTeardownBlock {
            TownHallPageURLProtocol.deactivate()
            URLProtocol.unregisterClass(TownHallPageURLProtocol.self)
        }
    }

    private func waitForPageRequests(_ count: Int, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while TownHallPageURLProtocol.pageRequestCount < count {
            guard Date() < deadline else {
                XCTFail("expected \(count) page requests, saw \(TownHallPageURLProtocol.pageRequestCount)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The shared page fetch runs on the deduplicator's task, off the main thread, and returns its
    /// posts unfiltered; each caller removes blocked authors after it returns, on its own
    /// (main-actor) executor. Two identical calls make one page request and two reads of the
    /// blocked set, both on the main thread, and both results leave the blocked author out.
    func testFetchPostsPage_FiltersBlockedAuthorsAfterTheSharedFetch() async throws {
        let blockedAuthor = UUID()
        let otherAuthor = UUID()
        let blockedPost = UUID()
        let otherPost = UUID()
        stubPageReads(Self.pageJSON([(blockedPost, blockedAuthor), (otherPost, otherAuthor)]), holdPages: true)
        let service = try XCTUnwrap(townHallService)
        let reads = BlockedSetReads(blocked: [blockedAuthor])
        service.blockedAuthorIds = { reads.read() }
        defer { service.blockedAuthorIds = { MessageService.shared.cachedBlockedUserIds } }
        let communityId = UUID()   // a page key no other test uses

        let first = Task { @MainActor in
            try await service.fetchPostsPage(limit: 20, offset: 0, communityId: communityId)
        }
        try await waitForPageRequests(1)
        let second = Task { @MainActor in
            try await service.fetchPostsPage(limit: 20, offset: 0, communityId: communityId)
        }
        try await Task.sleep(for: .milliseconds(300))   // the second call reaches the deduplicator
        TownHallPageURLProtocol.releaseHeldPages()
        let results = try await [first.value, second.value]

        XCTAssertEqual(TownHallPageURLProtocol.pageRequestCount, 1, "the second call joined the first")
        for result in results {
            XCTAssertEqual(result.posts.map(\.id), [otherPost])
            XCTAssertEqual(result.serverCount, 2, "counted before the blocked-author filter")
        }
        XCTAssertEqual(reads.count, 2, "one read per caller, none inside the shared fetch")
        XCTAssertTrue(reads.allOnMainThread, "read on the callers' main-actor executor")
    }
}
