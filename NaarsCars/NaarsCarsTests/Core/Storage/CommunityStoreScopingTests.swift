//
//  CommunityStoreScopingTests.swift
//  NaarsCarsTests
//
//  Fixture tests for the communityId mapper trio: rides, favors, notifications and
//  Town Hall posts carry their community through every SwiftData field site, and a row
//  cached by a build without the column (communityId nil) is rewritten by the next sync.
//  Town Hall scoping: scoped repository reads and the full sync's community scope.
//

import XCTest
import SwiftData
@testable import NaarsCars

/// Holds the scope read from the `.townHallPostsDidSync` notification (the expectation's
/// handler is a `@Sendable` closure, so it cannot assign a captured local).
private final class ReceivedSyncScope: @unchecked Sendable {
    var scope: TownHallSyncScope?
}

@MainActor
final class CommunityStoreScopingTests: XCTestCase {
    // Whole-second dates so the SwiftData round-trip compares equal to the payload values.
    private let base = Date(timeIntervalSince1970: 1_770_640_000)

    private let communityA = UUID(uuidString: "0C000000-0000-0000-0000-00000000000A")!
    private let communityB = UUID(uuidString: "0C000000-0000-0000-0000-00000000000B")!
    private let userId = UUID(uuidString: "0C000000-0000-0000-0000-000000000001")!
    private let rideId = UUID(uuidString: "0C000000-0000-0000-0000-000000000002")!
    private let favorId = UUID(uuidString: "0C000000-0000-0000-0000-000000000003")!
    private let notificationId = UUID(uuidString: "0C000000-0000-0000-0000-000000000004")!
    private let postId = UUID(uuidString: "0C000000-0000-0000-0000-000000000005")!

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: SDRide.self, SDFavor.self, SDNotification.self, SDTownHallPost.self,
            configurations: configuration
        )
    }

    private func ride(community: UUID?) -> Ride {
        Ride(
            id: rideId, userId: userId, date: base, time: "12:00:00",
            pickup: "Pickup", destination: "Destination",
            communityId: community, createdAt: base, updatedAt: base
        )
    }

    private func favor(community: UUID?) -> Favor {
        Favor(
            id: favorId, userId: userId, title: "Favor", location: "Location", date: base,
            communityId: community, createdAt: base, updatedAt: base
        )
    }

    private func notification(community: UUID?) -> AppNotification {
        AppNotification(
            id: notificationId, userId: userId, type: .rideClaimed, title: "Claimed",
            createdAt: base, rideId: rideId, communityId: community
        )
    }

    private func post(community: UUID?) -> TownHallPost {
        TownHallPost(
            id: postId, userId: userId, content: "Hello",
            communityId: community, createdAt: base, updatedAt: base
        )
    }

    private func storedRide(_ container: ModelContainer) throws -> SDRide? {
        try ModelContext(container).fetch(FetchDescriptor<SDRide>()).first
    }

    private func storedFavor(_ container: ModelContainer) throws -> SDFavor? {
        try ModelContext(container).fetch(FetchDescriptor<SDFavor>()).first
    }

    private func storedNotification(_ container: ModelContainer) throws -> SDNotification? {
        try ModelContext(container).fetch(FetchDescriptor<SDNotification>()).first
    }

    private func storedPost(_ container: ModelContainer) throws -> SDTownHallPost? {
        try ModelContext(container).fetch(FetchDescriptor<SDTownHallPost>()).first
    }

    private func communityId(of item: RequestItem) -> UUID? {
        switch item {
        case .ride(let ride): return ride.communityId
        case .favor(let favor): return favor.communityId
        }
    }

    // MARK: - BackgroundSyncActor: dashboard

    func testSyncAll_WritesCommunityIdForRideFavorAndNotification() async throws {
        let container = try makeContainer()
        let actor = BackgroundSyncActor(modelContainer: container)

        _ = try await actor.syncAllWithChangeDetection(
            rides: [ride(community: communityA)],
            favors: [favor(community: communityA)],
            notifications: [notification(community: communityA)]
        )

        XCTAssertEqual(try storedRide(container)?.communityId, communityA)
        XCTAssertEqual(try storedFavor(container)?.communityId, communityA)
        XCTAssertEqual(try storedNotification(container)?.communityId, communityA)
    }

    func testSyncAll_NilCommunityStaysNil() async throws {
        let container = try makeContainer()
        let actor = BackgroundSyncActor(modelContainer: container)

        _ = try await actor.syncAllWithChangeDetection(
            rides: [ride(community: nil)],
            favors: [favor(community: nil)],
            notifications: [notification(community: nil)]
        )

        XCTAssertNotNil(try storedRide(container))
        XCTAssertNil(try storedRide(container)?.communityId)
        XCTAssertNotNil(try storedFavor(container))
        XCTAssertNil(try storedFavor(container)?.communityId)
        XCTAssertNotNil(try storedNotification(container))
        XCTAssertNil(try storedNotification(container)?.communityId)
    }

    func testSyncAll_RewritesCachedRowWithNilCommunity() async throws {
        let container = try makeContainer()
        let actor = BackgroundSyncActor(modelContainer: container)

        // Rows as a build without the column cached them.
        _ = try await actor.syncAllWithChangeDetection(
            rides: [ride(community: nil)],
            favors: [favor(community: nil)],
            notifications: [notification(community: nil)]
        )
        // The payloads are stable: an identical resync changes nothing, so the rewrite
        // below can only come from the communityId comparison.
        let unchanged = try await actor.syncAllWithChangeDetection(
            rides: [ride(community: nil)],
            favors: [favor(community: nil)],
            notifications: [notification(community: nil)]
        )
        XCTAssertFalse(unchanged.ridesChanged)
        XCTAssertFalse(unchanged.favorsChanged)
        XCTAssertFalse(unchanged.notificationsChanged)

        let result = try await actor.syncAllWithChangeDetection(
            rides: [ride(community: communityA)],
            favors: [favor(community: communityA)],
            notifications: [notification(community: communityA)]
        )

        XCTAssertTrue(result.ridesChanged)
        XCTAssertTrue(result.favorsChanged)
        XCTAssertTrue(result.notificationsChanged)
        XCTAssertTrue(result.metrics.savedToStore)
        XCTAssertEqual(try storedRide(container)?.communityId, communityA)
        XCTAssertEqual(try storedFavor(container)?.communityId, communityA)
        XCTAssertEqual(try storedNotification(container)?.communityId, communityA)
    }

    func testUpsertRideAndFavorWithChangeDetection_WriteCommunityId() async throws {
        let container = try makeContainer()
        let actor = BackgroundSyncActor(modelContainer: container)

        // Insert path.
        let rideInsert = try await actor.upsertRideWithChangeDetection(ride(community: communityA))
        let favorInsert = try await actor.upsertFavorWithChangeDetection(favor(community: communityA))
        XCTAssertEqual(rideInsert.recordsInserted, 1)
        XCTAssertEqual(favorInsert.recordsInserted, 1)
        XCTAssertEqual(try storedRide(container)?.communityId, communityA)
        XCTAssertEqual(try storedFavor(container)?.communityId, communityA)

        // Update path: a cached nil row is rewritten.
        let otherContainer = try makeContainer()
        let otherActor = BackgroundSyncActor(modelContainer: otherContainer)
        _ = try await otherActor.upsertRideWithChangeDetection(ride(community: nil))
        _ = try await otherActor.upsertFavorWithChangeDetection(favor(community: nil))
        let rideUpdate = try await otherActor.upsertRideWithChangeDetection(ride(community: communityA))
        let favorUpdate = try await otherActor.upsertFavorWithChangeDetection(favor(community: communityA))
        XCTAssertEqual(rideUpdate.recordsMutated, 1)
        XCTAssertEqual(favorUpdate.recordsMutated, 1)
        XCTAssertEqual(try storedRide(otherContainer)?.communityId, communityA)
        XCTAssertEqual(try storedFavor(otherContainer)?.communityId, communityA)
    }

    // MARK: - BackgroundSyncActor: Town Hall posts

    func testSyncPosts_InsertsAndRewritesCommunityId() async throws {
        let container = try makeContainer()
        let actor = BackgroundSyncActor(modelContainer: container)
        _ = try await actor.syncPostsWithChangeDetection([post(community: communityA)])
        XCTAssertEqual(try storedPost(container)?.communityId, communityA)

        let cachedContainer = try makeContainer()
        let cachedActor = BackgroundSyncActor(modelContainer: cachedContainer)
        _ = try await cachedActor.syncPostsWithChangeDetection([post(community: nil)])
        XCTAssertNil(try storedPost(cachedContainer)?.communityId)

        let metrics = try await cachedActor.syncPostsWithChangeDetection([post(community: communityA)])
        XCTAssertTrue(metrics.savedToStore)
        XCTAssertEqual(metrics.recordsMutated, 1)
        XCTAssertEqual(try storedPost(cachedContainer)?.communityId, communityA)
    }

    func testUpsertPostWithChangeDetection_WritesCommunityId() async throws {
        let container = try makeContainer()
        let actor = BackgroundSyncActor(modelContainer: container)

        let inserted = try await actor.upsertPostWithChangeDetection(post(community: communityA))
        XCTAssertEqual(inserted.recordsInserted, 1)
        XCTAssertEqual(try storedPost(container)?.communityId, communityA)

        let cachedContainer = try makeContainer()
        let cachedActor = BackgroundSyncActor(modelContainer: cachedContainer)
        _ = try await cachedActor.upsertPostWithChangeDetection(post(community: nil))
        let updated = try await cachedActor.upsertPostWithChangeDetection(post(community: communityA))
        XCTAssertEqual(updated.recordsMutated, 1)
        XCTAssertTrue(updated.savedToStore)
        XCTAssertEqual(try storedPost(cachedContainer)?.communityId, communityA)
    }

    // MARK: - Reverse maps

    func testRequestFilterManager_ReverseMapCarriesCommunityId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        // Open, unclaimed and two days ahead, so the 12-hour window keeps both rows.
        let upcoming = Date().addingTimeInterval(2 * 86_400)
        let sdRide = SDRide(
            id: rideId, userId: userId, date: upcoming, time: "12:00:00",
            pickup: "Pickup", destination: "Destination", status: "open",
            createdAt: base, updatedAt: base, communityId: communityA
        )
        let sdFavor = SDFavor(
            id: favorId, userId: userId, title: "Favor", location: "Location",
            date: upcoming, time: "12:00:00", status: "open",
            createdAt: base, updatedAt: base, communityId: communityA
        )
        context.insert(sdRide)
        context.insert(sdFavor)
        try context.save()

        let items = RequestFilterManager().getFilteredRequests(rides: [sdRide], favors: [sdFavor], filter: .open)

        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertEqual(communityId(of: item), communityA)
        }
    }

    func testNotificationGroupingManager_CarriesCommunityId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sd = SDNotification(
            id: notificationId, userId: userId, type: NotificationType.rideClaimed.rawValue,
            title: "Claimed", createdAt: base, rideId: rideId, communityId: communityA
        )
        context.insert(sd)
        try context.save()

        let notifications = NotificationGroupingManager().getFilteredNotifications(sdNotifications: [sd])

        XCTAssertEqual(notifications.first?.communityId, communityA)
    }

    func testTownHallRepository_MapsAndRewritesCommunityId() throws {
        let container = try makeContainer()
        let repository = TownHallRepository()
        repository.setup(modelContext: ModelContext(container))
        try repository.upsertPosts([post(community: communityA)])
        XCTAssertEqual(try repository.getPosts(communityId: nil).first?.communityId, communityA)

        let cachedContainer = try makeContainer()
        let cachedContext = ModelContext(cachedContainer)
        cachedContext.insert(SDTownHallPost(
            id: postId, userId: userId, content: "Hello", createdAt: base, updatedAt: base
        ))
        try cachedContext.save()
        let cachedRepository = TownHallRepository()
        cachedRepository.setup(modelContext: cachedContext)
        XCTAssertNil(try cachedRepository.getPosts(communityId: nil).first?.communityId)

        try cachedRepository.upsertPosts([post(community: communityA)])

        XCTAssertEqual(try cachedRepository.getPosts(communityId: nil).first?.communityId, communityA)
    }

    // MARK: - Town Hall scoping

    /// Rows for A (newest), B and an unlabelled one cached by the previous build (oldest).
    private func scopedPosts() -> (a: TownHallPost, b: TownHallPost, unlabelled: TownHallPost) {
        let a = TownHallPost(
            id: UUID(uuidString: "0C000000-0000-0000-0000-0000000000A1")!, userId: userId, content: "A",
            communityId: communityA, createdAt: base.addingTimeInterval(20), updatedAt: base
        )
        let b = TownHallPost(
            id: UUID(uuidString: "0C000000-0000-0000-0000-0000000000B1")!, userId: userId, content: "B",
            communityId: communityB, createdAt: base.addingTimeInterval(10), updatedAt: base
        )
        let unlabelled = TownHallPost(
            id: UUID(uuidString: "0C000000-0000-0000-0000-0000000000C1")!, userId: userId, content: "Unlabelled",
            communityId: nil, createdAt: base, updatedAt: base
        )
        return (a, b, unlabelled)
    }

    func testGetPosts_NilCommunityReturnsEveryRow() throws {
        let container = try makeContainer()
        let repository = TownHallRepository()
        repository.setup(modelContext: ModelContext(container))
        let rows = scopedPosts()
        try repository.upsertPosts([rows.a, rows.b, rows.unlabelled])

        XCTAssertEqual(try repository.getPosts(communityId: nil).count, 3)
    }

    func testGetPosts_CommunityReturnsMatchingAndUnlabelledButNotOther() throws {
        let container = try makeContainer()
        let repository = TownHallRepository()
        repository.setup(modelContext: ModelContext(container))
        let rows = scopedPosts()
        try repository.upsertPosts([rows.a, rows.b, rows.unlabelled])

        XCTAssertEqual(try repository.getPosts(communityId: communityA).map(\.id), [rows.a.id, rows.unlabelled.id])
    }

    func testFullSync_FetchesTheScopeAndStampsItOnTheNotification() async throws {
        let container = try makeContainer()
        let rows = scopedPosts()
        let stub = StubTownHallPostFetcher(pagesByCommunity: [communityA: [rows.a]])
        let scopeA = communityA
        let engine = TownHallSyncEngine(
            repository: TownHallRepository(),
            postFetcher: stub,
            communityScope: { scopeA }
        )
        engine.setupBackgroundActor(container: container)

        let received = ReceivedSyncScope()
        let synced = expectation(forNotification: .townHallPostsDidSync, object: nil) { notification in
            received.scope = notification.userInfo?[TownHallSyncScope.userInfoKey] as? TownHallSyncScope
            return true
        }

        _ = try await engine.performFullSync()
        await fulfillment(of: [synced], timeout: 5)

        XCTAssertEqual(stub.requestedCommunityIds, [communityA])
        XCTAssertEqual(received.scope, .community(communityA))
    }

    // MARK: - Encoding

    func testTownHallPostEncode_OmitsNilCommunityIdAndWritesSetOne() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let nilData = try encoder.encode(post(community: nil))
        let nilObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: nilData) as? [String: Any])
        XCTAssertNil(nilObject["community_id"], "a nil community is omitted so the server resolves it")

        let setData = try encoder.encode(post(community: communityA))
        let setObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: setData) as? [String: Any])
        let encoded = try XCTUnwrap(setObject["community_id"] as? String)
        XCTAssertEqual(UUID(uuidString: encoded), communityA)
    }
}
