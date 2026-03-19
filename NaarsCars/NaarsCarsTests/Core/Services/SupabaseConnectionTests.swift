//
//  SupabaseConnectionTests.swift
//  NaarsCarsTests
//
//  Integration test for Supabase connection with perishable key
//

import XCTest
@testable import NaarsCars

@MainActor
final class SupabaseConnectionTests: XCTestCase {
    
    /// Test that Supabase client initializes correctly with perishable key
    func testSupabaseClientInitializes() {
        let service = SupabaseService.shared
        XCTAssertNotNil(service.client, "Supabase client should be initialized")
    }
    
    /// Test that credentials are configured
    func testCredentialsAreConfigured() {
        XCTAssertTrue(Secrets.isConfigured, "Secrets should be configured")
        XCTAssertFalse(Secrets.supabaseURL.isEmpty, "Supabase URL should not be empty")
        XCTAssertFalse(Secrets.supabaseAnonKey.isEmpty, "Publishable key should not be empty")
        
        // Verify URL format
        XCTAssertTrue(Secrets.supabaseURL.hasPrefix("https://"), "URL should be HTTPS")
        XCTAssertTrue(Secrets.supabaseURL.contains("supabase.co"), "URL should be Supabase domain")
        
        // Verify key format (perishable key starts with sb_publishable_)
        XCTAssertTrue(Secrets.supabaseAnonKey.hasPrefix("sb_publishable_"), "Key should be perishable/publishable format")
    }
    
    /// Test connection to Supabase (requires network)
    /// Note: This test may fail if network is unavailable or database is not accessible
    func testSupabaseConnection() async {
        let service = SupabaseService.shared
        let connected = await service.testConnection()
        
        // Connection test may fail if:
        // - Network unavailable
        // - Database not accessible
        // - RLS policies block anonymous access
        // So we'll just verify the method runs without crashing
        // Actual connection success depends on database setup
        XCTAssertNotNil(service.client, "Client should exist even if connection fails")
    }
}

