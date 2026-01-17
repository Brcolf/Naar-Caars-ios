//
//  NotificationServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for NotificationService
//

import XCTest
@testable import NaarsCars

@MainActor
final class NotificationServiceTests: XCTestCase {
    var notificationService: NotificationService!
    
    override func setUp() {
        super.setUp()
        notificationService = NotificationService.shared
    }
    
    /// Test that fetchNotifications returns pinned notifications first
    func testFetchNotifications_PinnedFirst() async throws {
        // Given: A user ID
        // Note: This test requires a real Supabase connection and authenticated user
        // In a real scenario, you'd mock the Supabase client
        
        guard let userId = AuthService.shared.currentUserId else {
            XCTSkip("No authenticated user for testing")
            return
        }
        
        // When: Fetching notifications
        do {
            let notifications = try await notificationService.fetchNotifications(userId: userId)
            
            // Then: Pinned notifications should come first
            var foundUnpinned = false
            for notification in notifications {
                if foundUnpinned && notification.pinned {
                    XCTFail("Pinned notification found after unpinned notification")
                    return
                }
                if !notification.pinned {
                    foundUnpinned = true
                }
            }
            
            // Test passes if we get here (either all pinned, all unpinned, or correct order)
            XCTAssertTrue(true, "Notifications are correctly ordered by pinned status")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            // The important thing is that the method signature and flow are correct
            XCTFail("Failed to fetch notifications: \(error.localizedDescription)")
        }
    }
    
    /// Test that markAsRead successfully marks a notification as read
    func testMarkAsRead_Success() async throws {
        // Given: A notification ID
        // Note: This test requires a real Supabase connection and authenticated user
        // In a real scenario, you'd mock the Supabase client
        
        guard let userId = AuthService.shared.currentUserId else {
            XCTSkip("No authenticated user for testing")
            return
        }
        
        // First, fetch notifications to get a notification ID
        do {
            let notifications = try await notificationService.fetchNotifications(userId: userId)
            
            guard let unreadNotification = notifications.first(where: { !$0.read }) else {
                XCTSkip("No unread notifications to test")
                return
            }
            
            // When: Marking as read
            try await notificationService.markAsRead(notificationId: unreadNotification.id)
            
            // Then: Notification should be marked as read
            // Verify by fetching again
            let updatedNotifications = try await notificationService.fetchNotifications(userId: userId)
            if let updatedNotification = updatedNotifications.first(where: { $0.id == unreadNotification.id }) {
                XCTAssertTrue(updatedNotification.read, "Notification should be marked as read")
            } else {
                XCTFail("Could not find updated notification")
            }
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Failed to mark notification as read: \(error.localizedDescription)")
        }
    }
    
    /// Test that fetchUnreadCount returns correct count
    func testFetchUnreadCount_ReturnsCorrectCount() async throws {
        // Given: A user ID
        guard let userId = AuthService.shared.currentUserId else {
            XCTSkip("No authenticated user for testing")
            return
        }
        
        // When: Fetching unread count
        do {
            let count = try await notificationService.fetchUnreadCount(userId: userId)
            
            // Then: Count should be non-negative
            XCTAssertGreaterThanOrEqual(count, 0, "Unread count should be non-negative")
            
            // Verify count matches actual unread notifications
            let notifications = try await notificationService.fetchNotifications(userId: userId)
            let actualUnreadCount = notifications.filter { !$0.read }.count
            XCTAssertEqual(count, actualUnreadCount, "Unread count should match actual unread notifications")
        } catch {
            XCTFail("Failed to fetch unread count: \(error.localizedDescription)")
        }
    }
    
    /// Test that markAllAsRead marks all notifications as read
    func testMarkAllAsRead_Success() async throws {
        // Given: A user ID
        guard let userId = AuthService.shared.currentUserId else {
            XCTSkip("No authenticated user for testing")
            return
        }
        
        // When: Marking all as read
        do {
            try await notificationService.markAllAsRead(userId: userId)
            
            // Then: All notifications should be read
            let notifications = try await notificationService.fetchNotifications(userId: userId)
            let unreadCount = notifications.filter { !$0.read }.count
            XCTAssertEqual(unreadCount, 0, "All notifications should be marked as read")
        } catch {
            XCTFail("Failed to mark all notifications as read: \(error.localizedDescription)")
        }
    }
}



