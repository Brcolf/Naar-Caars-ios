//
//  SupabaseService.swift
//  NaarsCars
//
//  Singleton service for Supabase client management
//

import Foundation
import Supabase
internal import Combine

/// Singleton service for managing Supabase client connection
@MainActor
final class SupabaseService: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared singleton instance
    static let shared = SupabaseService()
    
    // MARK: - Properties
    
    /// Supabase client instance
    let client: SupabaseClient
    
    /// Connection status
    @Published var isConnected: Bool = false
    
    /// Last connection error
    @Published var lastError: Error?
    
    // MARK: - Initialization
    
    private init() {
        // Initialize Supabase client with credentials from Secrets
        let urlString = Secrets.supabaseURL
        let anonKey = Secrets.supabaseAnonKey
        
        // Debug: Print deobfuscated URL (remove in production)
        print("🔐 [SupabaseService] Initializing...")
        print("🔐 [SupabaseService] URL: \(urlString.isEmpty ? "(empty)" : urlString)")
        print("🔐 [SupabaseService] URL length: \(urlString.count)")
        print("🔐 [SupabaseService] Anon key length: \(anonKey.count)")
        
        // Validate URL before creating client
        guard !urlString.isEmpty else {
            print("❌ [SupabaseService] ERROR: Supabase URL is empty!")
            print("❌ [SupabaseService] Please configure Secrets.swift with valid credentials")
            // Create a dummy client with placeholder URL to prevent crash
            // The testConnection() method will handle the error gracefully
            let placeholderURL = URL(string: "https://placeholder.supabase.co")!
            self.client = SupabaseClient(
                supabaseURL: placeholderURL,
                supabaseKey: "placeholder-key"
            )
            self.isConnected = false
            self.lastError = NSError(domain: "SupabaseService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Supabase URL is not configured. Please check Secrets.swift"
            ])
            print("⚠️ [SupabaseService] Using placeholder client - connection will fail")
            return
        }
        
        guard let url = URL(string: urlString), url.scheme == "https" else {
            print("❌ [SupabaseService] ERROR: Invalid Supabase URL format: '\(urlString)'")
            print("❌ [SupabaseService] URL must be a valid HTTPS URL")
            // Create a dummy client with placeholder URL to prevent crash
            let placeholderURL = URL(string: "https://placeholder.supabase.co")!
            self.client = SupabaseClient(
                supabaseURL: placeholderURL,
                supabaseKey: "placeholder-key"
            )
            self.isConnected = false
            self.lastError = NSError(domain: "SupabaseService", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid Supabase URL format: '\(urlString)'. Please check Secrets.swift"
            ])
            print("⚠️ [SupabaseService] Using placeholder client - connection will fail")
            return
        }
        
        guard !anonKey.isEmpty else {
            print("❌ [SupabaseService] ERROR: Supabase anon key is empty!")
            print("❌ [SupabaseService] Please configure Secrets.swift with valid credentials")
            // Create a dummy client with placeholder key to prevent crash
            self.client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: "placeholder-key"
            )
            self.isConnected = false
            self.lastError = NSError(domain: "SupabaseService", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Supabase anon key is not configured. Please check Secrets.swift"
            ])
            print("⚠️ [SupabaseService] Using placeholder client - connection will fail")
            return
        }
        
        // Configure Auth client to emit local session as initial session
        // This fixes the warning about incorrect behavior in session handling
        // See: https://github.com/supabase/supabase-swift/pull/822
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: KeychainLocalStorage(service: "com.naarscars.supabase.auth"),
            emitLocalSessionAsInitialSession: true
        )
        
        let options = SupabaseClientOptions(
            auth: authOptions
        )
        
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: options
        )
        
        print("✅ [SupabaseService] Client initialized successfully")
        // Credentials are now configured via obfuscated arrays
    }
    
    // MARK: - Connection Testing
    
    /// Tests the Supabase connection by running a simple query
    /// - Returns: True if connection successful, false otherwise
    func testConnection() async -> Bool {
        do {
            let urlString = Secrets.supabaseURL
            print("🔍 Testing Supabase connection...")
            print("🔍 Deobfuscated URL: \(urlString)")
            print("🔍 URL length: \(urlString.count)")
            
            // Verify URL is valid
            guard let url = URL(string: urlString), url.scheme == "https" else {
                print("❌ Invalid URL format: \(urlString)")
                isConnected = false
                lastError = NSError(domain: "SupabaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL format"])
                return false
            }
            
            // Try to fetch profiles count as a simple connection test
            print("🔍 Attempting to query profiles table...")
            _ = try await client
                .from("profiles")
                .select("id", head: true, count: .exact)
                .execute()
            
            // If we get a response (even if count is 0), connection works
            print("✅ Connection successful! Response received.")
            isConnected = true
            lastError = nil
            return true
        } catch {
            isConnected = false
            lastError = error
            print("❌ Supabase connection test failed")
            print("❌ Error: \(error)")
            print("❌ Error description: \(error.localizedDescription)")
            
            // Check if it's a network error
            if let urlError = error as? URLError {
                print("❌ URLError code: \(urlError.code.rawValue)")
                print("❌ URLError description: \(urlError.localizedDescription)")
            }
            
            // Check if it's a Supabase-specific error
            if let nsError = error as NSError? {
                print("❌ NSError domain: \(nsError.domain)")
                print("❌ NSError code: \(nsError.code)")
                print("❌ NSError userInfo: \(nsError.userInfo)")
            }
            
            return false
        }
    }
    
    // MARK: - Health Check
    
    /// Performs a health check on the Supabase connection
    /// - Returns: Health status message
    func healthCheck() async -> String {
        guard Secrets.isConfigured else {
            return "⚠️ Credentials not configured"
        }
        
        let connected = await testConnection()
        if connected {
            return "✅ Connected to Supabase"
        } else {
            return "❌ Connection failed: \(lastError?.localizedDescription ?? "Unknown error")"
        }
    }
}

