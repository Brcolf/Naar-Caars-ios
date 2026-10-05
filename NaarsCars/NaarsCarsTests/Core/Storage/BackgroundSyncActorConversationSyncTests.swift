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
}
