//
//  NotificationTypeDecodingTests.swift
//  NaarsCars
//
//  Unit tests for NotificationType contract and decoding
//

import XCTest
@testable import NaarsCars

final class NotificationTypeDecodingTests: XCTestCase {
    private var allTypes: [NotificationType] {
        [
            .message,
            .addedToConversation,
            .newRide,
            .rideUpdate,
            .rideClaimed,
            .rideUnclaimed,
            .rideCompleted,
            .newFavor,
            .favorUpdate,
            .favorClaimed,
            .favorUnclaimed,
            .favorCompleted,
            .completionReminder,
            .qaActivity,
            .qaQuestion,
            .qaAnswer,
            .review,
            .reviewReceived,
            .reviewReminder,
            .reviewRequest,
            .townHallPost,
            .townHallComment,
            .townHallReaction,
            .announcement,
            .adminAnnouncement,
            .broadcast,
            .pendingApproval,
            .userApproved,
            .userRejected,
            .other
        ]
    }

    func testFixturesContainExactlyAllNotificationTypeRawValues() {
        XCTAssertEqual(NotificationFixtures.allRawValues.count, 30)
        XCTAssertEqual(Set(NotificationFixtures.allRawValues), Set(allTypes.map(\.rawValue)))
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
}
