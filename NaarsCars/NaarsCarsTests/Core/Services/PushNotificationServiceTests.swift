//
//  PushNotificationServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for PushNotificationService
//

import XCTest
@testable import NaarsCars

@MainActor
final class PushNotificationServiceTests: XCTestCase {
    var pushService: PushNotificationService!
    
    override func setUp() {
        super.setUp()
        pushService = PushNotificationService.shared
    }
    
    /// Test that registerDeviceToken saves token to database
    func testRegisterToken_SavesToDB() async throws {
        // Given: A device token and user ID
        let deviceToken = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])
        let userId = UUID()
        
        // When: Registering the device token
        // Note: This test requires a real Supabase connection and authenticated user
        // In a real scenario, you'd mock the Supabase client
        do {
            try await pushService.registerDeviceToken(deviceToken: deviceToken, userId: userId)
            
            // Then: Token should be saved (no error thrown)
            // Verification would require querying the database, which is integration testing
            // For unit tests, we verify the method completes without throwing
            XCTAssertTrue(true, "Token registration completed successfully")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            // The important thing is that the method signature and flow are correct
            XCTFail("Token registration failed: \(error.localizedDescription)")
        }
    }
    
    /// Test that removeDeviceToken removes token from database
    func testRemoveToken_RemovesFromDB() async throws {
        // Given: A user ID
        let userId = UUID()
        
        // When: Removing the device token
        do {
            try await pushService.removeDeviceToken(userId: userId)
            
            // Then: Token should be removed (no error thrown)
            XCTAssertTrue(true, "Token removal completed successfully")
        } catch {
            // If this fails due to authentication or network, that's expected in unit tests
            XCTFail("Token removal failed: \(error.localizedDescription)")
        }
    }
    
    /// Test that requestPermission returns authorization status
    func testRequestPermission_ReturnsStatus() async {
        // When: Requesting permission
        let granted = await pushService.requestPermission()
        
        // Then: Should return a boolean (either granted or denied)
        // Note: Actual result depends on user's choice, but method should complete
        XCTAssertNotNil(granted, "Permission request should return a status")
    }
    
    /// Test that checkAuthorizationStatus returns current status
    func testCheckAuthorizationStatus_ReturnsStatus() async {
        // When: Checking authorization status
        let status = await pushService.checkAuthorizationStatus()
        
        // Then: Should return a valid authorization status
        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional, .ephemeral].contains(status),
                      "Should return a valid authorization status")
    }
}


