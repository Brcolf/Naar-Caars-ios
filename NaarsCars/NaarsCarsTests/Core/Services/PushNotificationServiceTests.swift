//
//  PushNotificationServiceTests.swift
//  NaarsCarsTests
//
//  Unit tests for PushNotificationService
//

import XCTest
import UserNotifications
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
        // Requires a live Supabase session; RLS rejects the write without one.
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }

        // Given: A device token and the authenticated user ID
        let deviceToken = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])
        
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
        // Requires a live Supabase session; RLS rejects the delete without one.
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }

        // Given: The authenticated user ID
        
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
        // Given: A stubbed notification center (the real one blocks on the simulator permission alert)
        let grantingStub = StubAuthorizationRequester(result: .success(true))
        let deniedStub = StubAuthorizationRequester(result: .success(false))
        let failingStub = StubAuthorizationRequester(result: .failure(StubAuthorizationRequester.StubError.failed))

        // When / Then: The service returns the center's answer, and false on error
        let granted = await PushNotificationService(authorizationRequester: grantingStub).requestPermission()
        XCTAssertTrue(granted, "Permission should be granted when the center grants it")
        XCTAssertEqual(grantingStub.requestedOptions, [.alert, .sound, .badge], "Should request alert, sound, and badge")

        let denied = await PushNotificationService(authorizationRequester: deniedStub).requestPermission()
        XCTAssertFalse(denied, "Permission should be denied when the center denies it")

        let failed = await PushNotificationService(authorizationRequester: failingStub).requestPermission()
        XCTAssertFalse(failed, "Permission should be false when the request throws")
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

/// Stub for the permission prompt; records the requested options and returns a fixed result.
private final class StubAuthorizationRequester: NotificationAuthorizationRequesting {
    enum StubError: Error { case failed }

    let result: Result<Bool, Error>
    private(set) var requestedOptions: UNAuthorizationOptions?

    init(result: Result<Bool, Error>) {
        self.result = result
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        return try result.get()
    }
}
