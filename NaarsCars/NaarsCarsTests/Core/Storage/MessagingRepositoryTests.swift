//
//  MessagingRepositoryTests.swift
//  NaarsCarsTests
//
//  Unit tests for MessagingRepository unread count updates
//

import XCTest
@testable import NaarsCars

@MainActor
final class MessagingRepositoryTests: XCTestCase {
    func testUpdatedUnreadCount_DecrementsWhenReadByAddsCurrentUser() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let previousReadBy: [UUID] = []
        let newReadBy: [UUID] = [currentUserId]

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 3,
            fromId: otherUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 2)
    }

    func testUpdatedUnreadCount_IncrementsWhenReadByRemovesCurrentUser() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let previousReadBy: [UUID] = [currentUserId]
        let newReadBy: [UUID] = []

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 1,
            fromId: otherUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 2)
    }

    func testUpdatedUnreadCount_DoesNotChangeForSenderMessages() {
        let currentUserId = UUID()
        let previousReadBy: [UUID] = []
        let newReadBy: [UUID] = [UUID()]

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 5,
            fromId: currentUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 5)
    }

    func testUpdatedUnreadCount_DoesNotGoBelowZero() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let previousReadBy: [UUID] = []
        let newReadBy: [UUID] = [currentUserId]

        let result = MessagingRepository.updatedUnreadCount(
            currentCount: 0,
            fromId: otherUserId,
            currentUserId: currentUserId,
            previousReadBy: previousReadBy,
            newReadBy: newReadBy
        )

        XCTAssertEqual(result, 0)
    }

    func testUpdatedUnreadCountForInsert_IncrementsForUnreadIncoming() {
        let currentUserId = UUID()
        let otherUserId = UUID()

        let result = MessagingRepository.updatedUnreadCountForInsert(
            currentCount: 1,
            fromId: otherUserId,
            currentUserId: currentUserId,
            readBy: []
        )

        XCTAssertEqual(result, 2)
    }

    func testUpdatedUnreadCountForInsert_DoesNotIncrementWhenRead() {
        let currentUserId = UUID()
        let otherUserId = UUID()

        let result = MessagingRepository.updatedUnreadCountForInsert(
            currentCount: 3,
            fromId: otherUserId,
            currentUserId: currentUserId,
            readBy: [currentUserId]
        )

        XCTAssertEqual(result, 3)
    }

    func testUpdatedUnreadCountForInsert_DoesNotIncrementForSender() {
        let currentUserId = UUID()

        let result = MessagingRepository.updatedUnreadCountForInsert(
            currentCount: 2,
            fromId: currentUserId,
            currentUserId: currentUserId,
            readBy: []
        )

        XCTAssertEqual(result, 2)
    }
}
