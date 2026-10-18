//
//  PushNotificationServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for PushNotificationService
//

import XCTest
import UserNotifications
import SwiftData
@testable import NaarsCars

@MainActor
final class PushNotificationServiceTests: XCTestCase {
    var pushService: PushNotificationService!
    
    override func setUp() {
        super.setUp()
        pushService = PushNotificationService.shared
    }
    
    /// Test that registerDeviceToken saves token to database
    func testRegisterToken_SavesToDB() async throws {
        // Requires a live Supabase session; RLS rejects the write without one.
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }

        // Given: A device token and the authenticated user ID
        let deviceToken = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])
        
        // When: Registering the device token
        // Note: This test requires a real Supabase connection and authenticated user
        // In a real scenario, you'd mock the Supabase client
        do {
            try await pushService.registerDeviceToken(deviceToken: deviceToken, userId: userId)
            
            // Then: Token should be saved (no error thrown)
            // Verification would require querying the database, which is integration testing
            // For unit tests, we verify the method completes without throwing
            XCTAssertTrue(true, "Token registration completed successfully")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            // The important thing is that the method signature and flow are correct
            XCTFail("Token registration failed: \(error.localizedDescription)")
        }
    }
    
    /// Test that removeDeviceToken removes token from database
    func testRemoveToken_RemovesFromDB() async throws {
        // Requires a live Supabase session; RLS rejects the delete without one.
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }

        // Given: The authenticated user ID
        
        // When: Removing the device token
        do {
            try await pushService.removeDeviceToken(userId: userId)
            
            // Then: Token should be removed (no error thrown)
            XCTAssertTrue(true, "Token removal completed successfully")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Token removal failed: \(error.localizedDescription)")
        }
    }
    
    /// Test that requestPermission returns authorization status
    func testRequestPermission_ReturnsStatus() async {
        // Given: A stubbed notification center (the real one blocks on the simulator permission alert)
        let grantingStub = StubAuthorizationRequester(result: .success(true))
        let deniedStub = StubAuthorizationRequester(result: .success(false))
        let failingStub = StubAuthorizationRequester(result: .failure(StubAuthorizationRequester.StubError.failed))

        // When / Then: The service returns the center's answer, and false on error
        let granted = await PushNotificationService(authorizationRequester: grantingStub).requestPermission()
        XCTAssertTrue(granted, "Permission should be granted when the center grants it")
        XCTAssertEqual(grantingStub.requestedOptions, [.alert, .sound, .badge], "Should request alert, sound, and badge")

        let denied = await PushNotificationService(authorizationRequester: deniedStub).requestPermission()
        XCTAssertFalse(denied, "Permission should be denied when the center denies it")

        let failed = await PushNotificationService(authorizationRequester: failingStub).requestPermission()
        XCTAssertFalse(failed, "Permission should be false when the request throws")
    }
    
    /// Test that checkAuthorizationStatus returns current status
    func testCheckAuthorizationStatus_ReturnsStatus() async {
        // When: Checking authorization status
        let status = await pushService.checkAuthorizationStatus()
        
        // Then: Should return a valid authorization status
        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional, .ephemeral].contains(status),
                      "Should return a valid authorization status")
    }

    // MARK: - Push refresh plan

    func testRefreshPlan_TownHallPostTargetsThePost() {
        let plan = PushRefreshPlan.make(userInfo: WebhookFixtures.townHallPostPushPayload)
        XCTAssertEqual(plan?.domains, [.townHall])
        XCTAssertEqual(plan?.entityId, WebhookFixtures.postId)
        XCTAssertEqual(plan?.refreshesMemberships, false)
    }

    func testRefreshPlan_TownHallCommentWithoutCommunityStillTargets() {
        let plan = PushRefreshPlan.make(userInfo: WebhookFixtures.townHallCommentPushPayload)
        XCTAssertEqual(plan?.domains, [.townHall])
        XCTAssertEqual(plan?.entityId, WebhookFixtures.postId)
    }

    func testRefreshPlan_RideWithCommunityKeyIsUnchanged() {
        let withCommunity = PushRefreshPlan.make(userInfo: WebhookFixtures.notificationPushPayloadWithCommunity)
        XCTAssertEqual(withCommunity, PushRefreshPlan(domains: [.dashboard], entityId: WebhookFixtures.rideId, refreshesMemberships: false))
        XCTAssertEqual(withCommunity, PushRefreshPlan.make(userInfo: WebhookFixtures.notificationPushPayload))
    }

    func testRefreshPlan_UserApprovedRefreshesMemberships() {
        let plan = PushRefreshPlan.make(userInfo: ["type": "user_approved"])
        XCTAssertEqual(plan?.refreshesMemberships, true)
        XCTAssertNil(plan?.entityId)
    }

    func testRefreshPlan_MissingOrUnknownTypeIsNil() {
        XCTAssertNil(PushRefreshPlan.make(userInfo: [:]))
        XCTAssertNil(PushRefreshPlan.make(userInfo: ["type": "some_future_type"]))
    }

    // MARK: - Targeted Town Hall sync

    /// "Does not throw" stands in for "leaves .townHall out of backoff": the coordinator moves a
    /// domain to `.failed(retryAfter:)` only when the engine throws.
    func testTargetedSync_UnreadablePostDeletesLocalRowWithoutThrowing() async throws {
        let postId = UUID(uuidString: "0D000000-0000-4000-8000-0000000000A1")!
        let container = try ModelContainer(
            for: SDTownHallPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let seed = ModelContext(container)
        seed.insert(SDTownHallPost(id: postId, userId: UUID(), content: "Cached"))
        try seed.save()

        let engine = TownHallSyncEngine(repository: TownHallRepository(), postFetcher: StubTownHallPostFetcher())
        engine.setupBackgroundActor(container: container)

        let first = try await engine.performTargetedSync(entityId: postId)
        XCTAssertEqual(first.recordsDeleted, 1)
        XCTAssertTrue(first.savedToStore)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SDTownHallPost>()).isEmpty)

        let second = try await engine.performTargetedSync(entityId: postId)
        XCTAssertEqual(second.recordsDeleted, 0)
        XCTAssertFalse(second.savedToStore)
    }

    func testTargetedSync_ReadablePostIsUpserted() async throws {
        let postId = UUID(uuidString: "0D000000-0000-4000-8000-0000000000A2")!
        let container = try ModelContainer(
            for: SDTownHallPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let post = CommunityFixtures.post(postId, community: CommunityFixtures.communityA, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        let engine = TownHallSyncEngine(repository: TownHallRepository(), postFetcher: StubTownHallPostFetcher(postsById: [postId: post]))
        engine.setupBackgroundActor(container: container)

        let metrics = try await engine.performTargetedSync(entityId: postId)
        XCTAssertEqual(metrics.recordsInserted, 1)
        let stored = try ModelContext(container).fetch(FetchDescriptor<SDTownHallPost>())
        XCTAssertEqual(stored.map(\.id), [postId])
        XCTAssertEqual(stored.first?.communityId, CommunityFixtures.communityA)
    }
}

/// Stub for the permission prompt; records the requested options and returns a fixed result.
private final class StubAuthorizationRequester: NotificationAuthorizationRequesting {
    enum StubError: Error { case failed }

    let result: Result<Bool, Error>
    private(set) var requestedOptions: UNAuthorizationOptions?

    init(result: Result<Bool, Error>) {
        self.result = result
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        return try result.get()
    }
}
