//
//  MessageServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for MessageService cache invalidation
//

import XCTest
import CoreLocation
import Realtime
@testable import NaarsCars

@MainActor
final class MessageServiceTests: XCTestCase {
    func testInvalidateConversationCachesClearsCacheForUsers() async throws {
        throw XCTSkip("Cache removed for SwiftData-first flow")
        let userId = UUID()
        let conversation = Conversation(createdBy: userId)
        let details = ConversationWithDetails(conversation: conversation)

        await CacheManager.shared.cacheConversations(userId: userId, [details])
        let cachedBefore = await CacheManager.shared.getCachedConversations(userId: userId)
        XCTAssertNotNil(cachedBefore, "Cache should be populated before invalidation")

        await MessageService.shared.invalidateConversationCaches(for: [userId])

        let cachedAfter = await CacheManager.shared.getCachedConversations(userId: userId)
        XCTAssertNil(cachedAfter, "Cache should be cleared after invalidation")
    }

    func testUnreadReadByFilterIncludesNullAndUserId() {
        let userId = UUID(uuidString: "0DA568D8-924C-4420-8853-206A48D277B6")!
        let filter = MessageService.unreadReadByFilter(userId: userId)
        XCTAssertEqual(filter, "read_by.is.null,read_by.not.cs.{\(userId.uuidString)}")
    }

    func testDecodeUnreadMessagesTreatsNullReadByAsEmpty() throws {
        let messageId = UUID(uuidString: "0DA568D8-924C-4420-8853-206A48D277B6")!
        let payload = """
        [{"id":"\(messageId.uuidString)","read_by":null}]
        """

        let messages = try MessageService.decodeUnreadMessages(from: Data(payload.utf8))

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].id, messageId)
        XCTAssertEqual(messages[0].readBy, [])
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

    func testDecodeUnreadMessagesHandlesMissingReadBy() throws {
        let messageId = UUID(uuidString: "5851C2CE-3D5A-4DF4-8FDB-7DEDE46E1E7A")!
        let payload = """
        [{"id":"\(messageId.uuidString)"}]
        """

        let messages = try MessageService.decodeUnreadMessages(from: Data(payload.utf8))

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].id, messageId)
        XCTAssertEqual(messages[0].readBy, [])
    }
}

@MainActor
final class ConversationDetailViewModelRealtimeTests: XCTestCase {
    func testRealtimeMessageInsertUpdatesViewModel() async throws {
        let conversationId = UUID()
        let viewModel = ConversationDetailViewModel(conversationId: conversationId)

        let newMessage = Message(
            id: UUID(),
            conversationId: conversationId,
            fromId: UUID(),
            text: "Hello from realtime"
        )

        NotificationCenter.default.post(
            name: NSNotification.Name("conversationUpdated"),
            object: conversationId,
            userInfo: ["message": newMessage]
        )

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline && !viewModel.messages.contains(where: { $0.id == newMessage.id }) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(
            viewModel.messages.contains(where: { $0.id == newMessage.id }),
            "Realtime notification should append message to view model without full reload"
        )
    }
}

@MainActor
final class MessagingSyncEngineTests: XCTestCase {
    func testShouldIgnoreReadByUpdate_WhenOnlyReadByAddsCurrentUser() {
        let currentUserId = UUID()
        let base = makeBaseRecord(text: "Hi")
        var record = base
        var oldRecord = base
        record["read_by"] = .array([.string(currentUserId.uuidString)])
        oldRecord["read_by"] = .array([])

        let shouldIgnore = MessagingSyncEngine.shouldIgnoreReadByUpdate(
            record: record,
            oldRecord: oldRecord,
            currentUserId: currentUserId
        )

        XCTAssertTrue(shouldIgnore)
    }

    func testShouldIgnoreReadByUpdate_ReturnsFalseWhenOtherFieldsChange() {
        let currentUserId = UUID()
        var record = makeBaseRecord(text: "Hello")
        var oldRecord = makeBaseRecord(text: "Hi")
        record["read_by"] = .array([.string(currentUserId.uuidString)])
        oldRecord["read_by"] = .array([])

        let shouldIgnore = MessagingSyncEngine.shouldIgnoreReadByUpdate(
            record: record,
            oldRecord: oldRecord,
            currentUserId: currentUserId
        )

        XCTAssertFalse(shouldIgnore)
    }

    func testShouldIgnoreReadByUpdate_ReturnsFalseForOtherUserRead() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let base = makeBaseRecord(text: "Hi")
        var record = base
        var oldRecord = base
        record["read_by"] = .array([.string(otherUserId.uuidString)])
        oldRecord["read_by"] = .array([])

        let shouldIgnore = MessagingSyncEngine.shouldIgnoreReadByUpdate(
            record: record,
            oldRecord: oldRecord,
            currentUserId: currentUserId
        )

        XCTAssertFalse(shouldIgnore)
    }

    private func makeBaseRecord(text: String) -> [String: AnyJSON] {
        let messageId = UUID()
        let conversationId = UUID()
        let fromId = UUID()
        return [
            "id": .string(messageId.uuidString),
            "conversation_id": .string(conversationId.uuidString),
            "from_id": .string(fromId.uuidString),
            "text": .string(text),
            "message_type": .string("text"),
            "updated_at": .string("2026-01-01T00:00:00Z")
        ]
    }
}

final class RideCostEstimatorTests: XCTestCase {
    func testTimeOfDayMultiplierWeekdayMorningRush() {
        let calendar = makeCalendar()
        let date = makeDate(year: 2026, month: 1, day: 29, hour: 8, calendar: calendar)

        let multiplier = RideCostEstimator.timeOfDayMultiplier(date: date, calendar: calendar)

        XCTAssertEqual(multiplier, 1.5)
    }

    func testTimeOfDayMultiplierWeekendLateNight() {
        let calendar = makeCalendar()
        let date = makeDate(year: 2026, month: 1, day: 31, hour: 1, calendar: calendar)

        let multiplier = RideCostEstimator.timeOfDayMultiplier(date: date, calendar: calendar)

        XCTAssertEqual(multiplier, 1.7)
    }

    func testLocationMultiplierUsesHighestZone() {
        let zones = [
            RideCostEstimator.PricingZone(
                name: "Test Airport",
                multiplier: 1.5,
                polygon: [
                    CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
                    CLLocationCoordinate2D(latitude: 0.0, longitude: 1.0),
                    CLLocationCoordinate2D(latitude: 1.0, longitude: 1.0),
                    CLLocationCoordinate2D(latitude: 1.0, longitude: 0.0)
                ]
            ),
            RideCostEstimator.PricingZone(
                name: "Test Downtown",
                multiplier: 1.3,
                polygon: [
                    CLLocationCoordinate2D(latitude: 0.25, longitude: 0.25),
                    CLLocationCoordinate2D(latitude: 0.25, longitude: 0.75),
                    CLLocationCoordinate2D(latitude: 0.75, longitude: 0.75),
                    CLLocationCoordinate2D(latitude: 0.75, longitude: 0.25)
                ]
            )
        ]

        let pickup = CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5)
        let destination = CLLocationCoordinate2D(latitude: 2.0, longitude: 2.0)

        let multiplier = RideCostEstimator.locationMultiplier(
            pickup: pickup,
            destination: destination,
            zones: zones
        )

        XCTAssertEqual(multiplier, 1.5)
    }

    func testEstimateCostDetailsAppliesMultipliers() {
        let calendar = makeCalendar()
        let date = makeDate(year: 2026, month: 1, day: 29, hour: 12, calendar: calendar)

        let estimate = RideCostEstimator.estimateCostDetails(
            distanceMiles: 10.0,
            timeMinutes: 20.0,
            date: date,
            locationMultiplier: 1.3,
            weatherMultiplier: 1.2,
            calendar: calendar
        )

        XCTAssertEqual(estimate.multipliers.timeOfDay, 1.0)
        XCTAssertEqual(estimate.totalMultiplier, 1.56, accuracy: 0.001)
        XCTAssertEqual(estimate.finalPrice, 42.12, accuracy: 0.01)
        XCTAssertEqual(estimate.estimatedTimeMinutes, 20.0, accuracy: 0.001)
        XCTAssertEqual(estimate.distanceMiles, 10.0, accuracy: 0.001)
    }

    func testEstimateCostDetailsEnforcesMinimumFare() {
        let calendar = makeCalendar()
        let date = makeDate(year: 2026, month: 1, day: 29, hour: 12, calendar: calendar)

        let estimate = RideCostEstimator.estimateCostDetails(
            distanceMiles: 0.5,
            timeMinutes: 2.0,
            date: date,
            locationMultiplier: 1.0,
            weatherMultiplier: 1.0,
            calendar: calendar
        )

        XCTAssertEqual(estimate.finalPrice, 7.0, accuracy: 0.01)
    }

    private func makeCalendar(timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.calendar = calendar

        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
