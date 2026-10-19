//
//  NotificationTypeDecodingTests.swift
//  NaarsCars
//
//  Unit tests for NotificationType contract and decoding
//

import XCTest
import SwiftData
@testable import NaarsCars

final class NotificationTypeDecodingTests: XCTestCase {
    private var allTypes: [NotificationType] { NotificationType.allCases }

    func testFixturesContainExactlyAllNotificationTypeRawValues() {
        XCTAssertEqual(NotificationFixtures.allRawValues.count, 34)
        XCTAssertEqual(Set(NotificationFixtures.allRawValues), Set(NotificationType.allCases.map(\.rawValue)))
    }

    func testRoundTripDecodingForAllNotificationTypes() {
        for type in allTypes {
            let decoded = NotificationType(rawValue: type.rawValue)
            XCTAssertEqual(decoded, type, "Round-trip failed for \(type.rawValue)")
        }
    }

    func testPreferenceKeyMappingMatchesFixtureForAllNotificationTypes() {
        for type in allTypes {
            XCTAssertEqual(
                type.preferenceKey,
                NotificationFixtures.preferenceMapping[type.rawValue] ?? nil,
                "Preference mapping mismatch for \(type.rawValue)"
            )
        }
    }

    func testCanBeDisabledMatchesMandatoryTypeFixture() {
        for type in allTypes {
            let isMandatory = NotificationFixtures.mandatoryTypes.contains(type.rawValue)
            XCTAssertEqual(type.canBeDisabled, !isMandatory, "canBeDisabled mismatch for \(type.rawValue)")
        }
    }

    func testIconIsNonEmptyForAllNotificationTypes() {
        for type in allTypes {
            XCTAssertFalse(type.icon.isEmpty, "Expected non-empty icon for \(type.rawValue)")
        }
    }

    func testUnknownRawValueReturnsNil() {
        XCTAssertNil(NotificationType(rawValue: "not_a_real_notification_type"))
    }

    func testUnknownFutureRawValueDecodesAsOther() throws {
        let decoded = try JSONDecoder().decode(NotificationType.self, from: Data("\"probe_future_type\"".utf8))
        XCTAssertEqual(decoded, .other)
    }

    func testDecode_MembershipUpdate() throws {
        let decoded = try JSONDecoder().decode(NotificationType.self, from: Data("\"membership_update\"".utf8))
        XCTAssertEqual(decoded, .membershipUpdate)

        let json = #"{"id":"0A000000-0000-0000-0000-000000000004","user_id":"0A000000-0000-0000-0000-000000000002","type":"membership_update","title":"T","body":null,"read":false,"pinned":false,"created_at":"2026-10-19T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notification = try decoder.decode(AppNotification.self, from: Data(json.utf8))
        XCTAssertEqual(notification.type, .membershipUpdate)
        XCTAssertEqual(notification.typeRawValue, "membership_update")
    }

    func testKnownRawValueDecodesAsItself() throws {
        let decoded = try JSONDecoder().decode(NotificationType.self, from: Data("\"town_hall_post\"".utf8))
        XCTAssertEqual(decoded, .townHallPost)
    }

    func testEncodingWritesRawValue() throws {
        let encoder = JSONEncoder()
        XCTAssertEqual(String(data: try encoder.encode([NotificationType.other]), encoding: .utf8), "[\"other\"]")
        XCTAssertEqual(String(data: try encoder.encode([NotificationType.accountRestricted]), encoding: .utf8), "[\"account_restricted\"]")
    }

    func testAppNotificationWithUnknownTypeDecodes() throws {
        let json = #"{"id":"0A000000-0000-0000-0000-000000000001","user_id":"0A000000-0000-0000-0000-000000000002","type":"probe_future_type","title":"T","body":null,"read":false,"pinned":false,"created_at":"2026-10-17T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(AppNotification.self, from: Data(json.utf8)).type, .other)
    }

    // MARK: - Unknown type kept in the cache

    private static let unknownTypeJSON = #"{"id":"0A000000-0000-0000-0000-000000000003","user_id":"0A000000-0000-0000-0000-000000000002","type":"probe_future_type","title":"T","body":null,"read":false,"pinned":false,"created_at":"2026-10-17T12:00:00Z"}"#

    private func decodeUnknownTypeNotification() throws -> AppNotification {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppNotification.self, from: Data(Self.unknownTypeJSON.utf8))
    }

    func testAppNotificationWithUnknownTypeKeepsRawValue() throws {
        let notification = try decodeUnknownTypeNotification()
        XCTAssertEqual(notification.type, .other)
        XCTAssertEqual(notification.typeRawValue, "probe_future_type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(notification)) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "probe_future_type")
    }

    func testKnownTypeRawValueMatchesType() {
        let notification = AppNotification(userId: UUID(), type: .townHallPost, title: "T")
        XCTAssertEqual(notification.typeRawValue, "town_hall_post")
    }

    /// The cached row stores the server's string, not "other", so a later build that knows the
    /// type decodes it; this build still reads it back as `.other`.
    @MainActor
    func testSyncStoresOriginalRawTypeInCachedRow() async throws {
        let notification = try decodeUnknownTypeNotification()
        let container = try ModelContainer(
            for: SDNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let actor = BackgroundSyncActor(modelContainer: container)
        try await actor.syncNotifications([notification])

        let rows = try ModelContext(container).fetch(FetchDescriptor<SDNotification>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.type, "probe_future_type")
        XCTAssertEqual(NotificationType(rawValue: rows.first?.type ?? ""), nil)

        let mapped = NotificationGroupingManager().getFilteredNotifications(sdNotifications: rows)
        XCTAssertEqual(mapped.first?.type, .other)
        XCTAssertEqual(mapped.first?.typeRawValue, "probe_future_type")
    }

    /// A row an older build stored as "other" is rewritten when the server row is synced again.
    @MainActor
    func testSyncHealsRowStoredAsOther() async throws {
        let notification = try decodeUnknownTypeNotification()
        let container = try ModelContainer(
            for: SDNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(SDNotification(
            id: notification.id, userId: notification.userId, type: "other",
            title: notification.title, body: nil, read: false, pinned: false,
            createdAt: notification.createdAt
        ))
        try context.save()

        let actor = BackgroundSyncActor(modelContainer: container)
        try await actor.syncNotifications([notification])

        let rows = try ModelContext(container).fetch(FetchDescriptor<SDNotification>())
        XCTAssertEqual(rows.first?.type, "probe_future_type")
    }
}
