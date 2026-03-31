//
//  NotificationTypeDomainMappingTests.swift
//  NaarsCars
//

import XCTest
@testable import NaarsCars

final class NotificationTypeDomainMappingTests: XCTestCase {

    func testEveryNotificationTypeHasAffectedDomains() {
        for type in NotificationType.allCases {
            let domains = type.affectedDomains
            if type == .other {
                XCTAssertTrue(domains.isEmpty, "\(type) should have no affected domains")
            }
        }
    }

    func testMessageTypesMapToConversations() {
        XCTAssertEqual(NotificationType.message.affectedDomains, [.conversations])
        XCTAssertEqual(NotificationType.addedToConversation.affectedDomains, [.conversations])
    }

    func testRideTypesMapToDashboard() {
        let rideTypes: [NotificationType] = [.newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted]
        for type in rideTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testFavorTypesMapToDashboard() {
        let favorTypes: [NotificationType] = [.newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted]
        for type in favorTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testQATypesMapToDashboard() {
        let qaTypes: [NotificationType] = [.qaActivity, .qaQuestion, .qaAnswer]
        for type in qaTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testReviewTypesMapToDashboard() {
        let reviewTypes: [NotificationType] = [.review, .reviewReceived, .reviewReminder, .reviewRequest]
        for type in reviewTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testTownHallTypesMapToTownHall() {
        let thTypes: [NotificationType] = [.townHallPost, .townHallComment, .townHallReaction, .announcement, .adminAnnouncement, .broadcast]
        for type in thTypes {
            XCTAssertEqual(type.affectedDomains, [.townHall], "\(type) should map to townHall")
        }
    }

    func testAdminTypesMapToDashboard() {
        let adminTypes: [NotificationType] = [.pendingApproval, .userApproved, .userRejected, .accountRestricted, .contentReported, .completionReminder]
        for type in adminTypes {
            XCTAssertEqual(type.affectedDomains, [.dashboard], "\(type) should map to dashboard")
        }
    }

    func testEntityIdKeyPresent() {
        XCTAssertEqual(NotificationType.rideClaimed.entityIdKey, "ride_id")
        XCTAssertEqual(NotificationType.newRide.entityIdKey, "ride_id")
        XCTAssertEqual(NotificationType.favorUpdate.entityIdKey, "favor_id")
        XCTAssertEqual(NotificationType.favorClaimed.entityIdKey, "favor_id")
        XCTAssertEqual(NotificationType.townHallPost.entityIdKey, "post_id")
        XCTAssertEqual(NotificationType.townHallComment.entityIdKey, "post_id")
        XCTAssertEqual(NotificationType.message.entityIdKey, "conversation_id")
        XCTAssertEqual(NotificationType.addedToConversation.entityIdKey, "conversation_id")
    }

    func testEntityIdKeyNilForTypesWithoutEntity() {
        XCTAssertNil(NotificationType.completionReminder.entityIdKey)
        XCTAssertNil(NotificationType.other.entityIdKey)
        XCTAssertNil(NotificationType.review.entityIdKey)
        XCTAssertNil(NotificationType.pendingApproval.entityIdKey)
        XCTAssertNil(NotificationType.accountRestricted.entityIdKey)
        XCTAssertNil(NotificationType.broadcast.entityIdKey)
    }
}
