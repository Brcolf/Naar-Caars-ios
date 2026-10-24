//
//  BackgroundSyncActorConversationSyncTests.swift
//  NaarsCarsTests
//
//  Fixture tests for BackgroundSyncActor.syncConversations removal reconciliation
//

import XCTest
import SwiftData
@testable import NaarsCars

@MainActor
final class BackgroundSyncActorConversationSyncTests: XCTestCase {
    private let currentUserId = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

    // Whole-second dates so the SwiftData round-trip compares equal to the payload values.
    private let base = Date(timeIntervalSince1970: 1_770_640_000)

    private let newestId = UUID(uuidString: "0000000A-0000-0000-0000-000000000001")!
    private let absentWithinWindowId = UUID(uuidString: "0000000B-0000-0000-0000-000000000002")!
    private let oldestInPageId = UUID(uuidString: "0000000C-0000-0000-0000-000000000003")!
    private let absentOlderThanWindowId = UUID(uuidString: "0000000D-0000-0000-0000-000000000004")!

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: SDConversation.self, SDMessage.self, configurations: configuration)
    }

    /// Seeds four local conversations: two that the server page will return (newest and oldest in
    /// page), one absent but inside the page window, and one absent and older than the window.
    private func seedLocalConversations(in container: ModelContainer) throws {
        let context = ModelContext(container)
        let rows: [(UUID, TimeInterval)] = [
            (newestId, 0),
            (absentWithinWindowId, -50),
            (oldestInPageId, -100),
            (absentOlderThanWindowId, -10_000)
        ]
        for (id, offset) in rows {
            context.insert(SDConversation(
                id: id,
                createdBy: currentUserId,
                createdAt: base.addingTimeInterval(offset),
                updatedAt: base.addingTimeInterval(offset),
                participantIds: [currentUserId]
            ))
        }
        try context.save()
    }

    /// The server page: newest and oldest-in-page, ordered by updatedAt DESC like the RPC.
    private func serverPagePayloads() -> [ConversationSyncPayload] {
        let rows: [(UUID, TimeInterval)] = [(newestId, 0), (oldestInPageId, -100)]
        return rows.map { id, offset in
            let conversation = Conversation(
                id: id,
                createdBy: currentUserId,
                createdAt: base.addingTimeInterval(offset),
                updatedAt: base.addingTimeInterval(offset)
            )
            return ConversationSyncPayload(from: ConversationWithDetails(conversation: conversation), currentUserId: currentUserId)
        }
    }

    private func remainingConversationIds(in container: ModelContainer) throws -> Set<UUID> {
        let context = ModelContext(container)
        return Set(try context.fetch(FetchDescriptor<SDConversation>()).map { $0.id })
    }

    func testSyncConversations_FullPage_DeletesAbsentWithinWindowAndKeepsOlder() async throws {
        let container = try makeContainer()
        try seedLocalConversations(in: container)
        let actor = BackgroundSyncActor(modelContainer: container)

        let changedIds = try await actor.syncConversations(
            serverPagePayloads(), currentUserId: currentUserId, serverSetIsComplete: false
        )

        XCTAssertTrue(changedIds.contains(absentWithinWindowId))
        XCTAssertFalse(changedIds.contains(absentOlderThanWindowId))
        XCTAssertEqual(
            try remainingConversationIds(in: container),
            [newestId, oldestInPageId, absentOlderThanWindowId]
        )
    }

    func testSyncConversations_CompleteServerSet_DeletesEveryAbsentConversation() async throws {
        let container = try makeContainer()
        try seedLocalConversations(in: container)
        let actor = BackgroundSyncActor(modelContainer: container)

        let changedIds = try await actor.syncConversations(
            serverPagePayloads(), currentUserId: currentUserId, serverSetIsComplete: true
        )

        XCTAssertTrue(changedIds.contains(absentWithinWindowId))
        XCTAssertTrue(changedIds.contains(absentOlderThanWindowId))
        XCTAssertEqual(try remainingConversationIds(in: container), [newestId, oldestInPageId])
    }

    func testSyncConversations_UnchangedPage_ReturnsEmptySetAndDeletesNothing() async throws {
        let container = try makeContainer()
        try seedLocalConversations(in: container)
        let actor = BackgroundSyncActor(modelContainer: container)
        // Page contains every local conversation, so nothing is absent and nothing differs.
        let rows: [(UUID, TimeInterval)] = [
            (newestId, 0), (absentWithinWindowId, -50), (oldestInPageId, -100), (absentOlderThanWindowId, -10_000)
        ]
        let payloads = rows.map { id, offset in
            let conversation = Conversation(
                id: id,
                createdBy: currentUserId,
                createdAt: base.addingTimeInterval(offset),
                updatedAt: base.addingTimeInterval(offset)
            )
            return ConversationSyncPayload(from: ConversationWithDetails(conversation: conversation), currentUserId: currentUserId)
        }

        let changedIds = try await actor.syncConversations(payloads, currentUserId: currentUserId, serverSetIsComplete: true)

        XCTAssertTrue(changedIds.isEmpty)
        XCTAssertEqual(
            try remainingConversationIds(in: container),
            [newestId, absentWithinWindowId, oldestInPageId, absentOlderThanWindowId]
        )
    }

    // MARK: - Interleaved saves (review of 138538f)

    /// Since 138538f the dashboard sync enters BackgroundSyncActor from a detached task, so the
    /// actor's job runs off the main thread and its save can interleave with a main-context save of
    /// the same rows (NotificationsListViewModel marking notifications read). Runs the two side by
    /// side 50 times on a SQLite store, as the app does: the actor's save must not throw. Which
    /// `read` value the store holds after each round is attached to the result as
    /// "interleaved-saves". Observed on 2026-10-20 (two runs): no save threw; the later save won
    /// the whole row, so a main-context save from a snapshot older than the actor's save put back
    /// the previous round's title, which the main context never changed.
    func testDashboardSyncInterleavedWithMainContextSaves_ActorSaveDoesNotThrow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackgroundSyncActorInterleave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: SDRide.self, SDFavor.self, SDNotification.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("store.sqlite"))
        )
        let userId = currentUserId
        let createdAt = base
        let ids = (0..<20).map { _ in UUID() }
        let main = container.mainContext
        for id in ids {
            main.insert(SDNotification(id: id, userId: userId, type: "town_hall_post", title: "seed", createdAt: createdAt))
        }
        try main.save()
        let actor = BackgroundSyncActor(modelContainer: container)

        var actorErrors: [String] = []
        var mainErrors: [String] = []
        var actorWon = 0
        var mainWon = 0
        var mixed = 0
        var actorTitleKept = 0
        var unusualRounds: [String] = []
        for round in 0..<50 {
            let actorRead = round % 2 == 0
            let payload = ids.map { id in
                AppNotification(id: id, userId: userId, type: .townHallPost, title: "actor \(round)",
                                read: actorRead, createdAt: createdAt)
            }
            let job = Task.detached(priority: .userInitiated) {
                try await actor.syncAllWithChangeDetection(rides: [], favors: [], notifications: payload)
            }
            // Vary where the main save lands relative to the actor's job.
            switch round % 3 {
            case 1: await Task.yield()
            case 2: try await Task.sleep(for: .milliseconds(1))
            default: break
            }
            for row in try main.fetch(FetchDescriptor<SDNotification>()) {
                row.read = !actorRead
            }
            do { try main.save() } catch { mainErrors.append("round \(round): \(error)") }
            do { _ = try await job.value } catch { actorErrors.append("round \(round): \(error)") }

            let stored = try ModelContext(container).fetch(FetchDescriptor<SDNotification>())
            if stored.allSatisfy({ $0.read == actorRead }) {
                actorWon += 1
            } else if stored.allSatisfy({ $0.read != actorRead }) {
                mainWon += 1
            } else {
                mixed += 1
            }
            if stored.allSatisfy({ $0.title == "actor \(round)" }) {
                actorTitleKept += 1
            } else if unusualRounds.count < 5 {
                unusualRounds.append("round \(round): \(stored.count) rows, read \(stored.filter(\.read).count) true, titles \(Set(stored.map(\.title)).sorted())")
            }
        }

        let summary = """
        50 rounds, 20 rows: read held the actor's value in \(actorWon) rounds, the main context's in \(mainWon), \
        mixed in \(mixed); the actor's title survived in \(actorTitleKept). Actor save errors: \(actorErrors.count). \
        Main save errors: \(mainErrors.count). \(actorErrors.prefix(3)) \(mainErrors.prefix(3)) \(unusualRounds)
        """
        print("[interleaved-saves] \(summary)")
        let attachment = XCTAttachment(string: summary)
        attachment.name = "interleaved-saves"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(actorErrors, [], "the actor's save threw while a main-context save of the same rows interleaved")
    }
}
