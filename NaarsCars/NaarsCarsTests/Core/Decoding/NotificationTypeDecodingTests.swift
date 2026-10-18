//
//  NotificationTypeDecodingTests.swift
//  NaarsCars
//
//  Unit tests for NotificationType contract and decoding
//

import XCTest
@testable import NaarsCars

final class NotificationTypeDecodingTests: XCTestCase {
    private var allTypes: [NotificationType] { NotificationType.allCases }

    func testFixturesContainExactlyAllNotificationTypeRawValues() {
        XCTAssertEqual(NotificationFixtures.allRawValues.count, 33)
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

    func testUnknownRawValueDecodesAsOther() throws {
        let decoded = try JSONDecoder().decode(NotificationType.self, from: Data("\"membership_update\"".utf8))
        XCTAssertEqual(decoded, .other)
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
        let json = #"{"id":"0A000000-0000-0000-0000-000000000001","user_id":"0A000000-0000-0000-0000-000000000002","type":"membership_update","title":"T","body":null,"read":false,"pinned":false,"created_at":"2026-10-17T12:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(AppNotification.self, from: Data(json.utf8)).type, .other)
    }
}
