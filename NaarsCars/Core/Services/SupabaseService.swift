//
//  SupabaseService.swift
//  NaarsCars
//
//  Singleton service for Supabase client management
//

import Foundation
import Supabase
import OSLog
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

    private var authStateTask: Task<Void, Never>?

    
    // MARK: - Initialization
    
    private init() {
        // Initialize Supabase client with credentials from Secrets
        let urlString = Secrets.supabaseURL
        let anonKey = Secrets.supabaseAnonKey
        
        #if DEBUG
        AppLogger.auth.debug("[SupabaseService] Initializing...")
        AppLogger.auth.debug("[SupabaseService] URL: \(urlString.isEmpty ? "(empty)" : urlString)")
        AppLogger.auth.debug("[SupabaseService] URL length: \(urlString.count)")
        AppLogger.auth.debug("[SupabaseService] Anon key length: \(anonKey.count)")
        #endif
        
        // Validate URL before creating client
        guard !urlString.isEmpty else {
            AppLogger.auth.error("[SupabaseService] Supabase URL is empty!")
            AppLogger.auth.error("[SupabaseService] Please configure Secrets.swift with valid credentials")
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
            AppLogger.auth.warning("[SupabaseService] Using placeholder client - connection will fail")
            return
        }
        
        guard let url = URL(string: urlString), url.scheme == "https" else {
            AppLogger.auth.error("[SupabaseService] Invalid Supabase URL format: '\(urlString)'")
            AppLogger.auth.error("[SupabaseService] URL must be a valid HTTPS URL")
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
            AppLogger.auth.warning("[SupabaseService] Using placeholder client - connection will fail")
            return
        }
        
        guard !anonKey.isEmpty else {
            AppLogger.auth.error("[SupabaseService] Supabase anon key is empty!")
            AppLogger.auth.error("[SupabaseService] Please configure Secrets.swift with valid credentials")
            // Create a dummy client with placeholder key to prevent crash
            self.client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: "placeholder-key"
            )
            self.isConnected = false
            self.lastError = NSError(domain: "SupabaseService", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Supabase anon key is not configured. Please check Secrets.swift"
            ])
            AppLogger.auth.warning("[SupabaseService] Using placeholder client - connection will fail")
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
        
        AppLogger.auth.info("[SupabaseService] Client initialized successfully")
        // Credentials are now configured via obfuscated arrays

        // Keep auth session fresh so realtime auth stays valid
        Task { [client] in
            await client.auth.startAutoRefresh()
        }

        startAuthStateObserver()

    }

    private func startAuthStateObserver() {
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self = self else { return }
            for await (event, session) in await self.client.auth.authStateChanges {
                await self.handleAuthStateChange(event: event, session: session)
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedOut:
            Task.detached { [client] in
                AppLogger.realtime.info("[SupabaseService] Auth signed out; disconnecting realtime")
                await client.realtimeV2.disconnect()
            }
        default:
            if let token = session?.accessToken, !token.isEmpty {
                Task.detached { [client] in
                    AppLogger.realtime.info("[SupabaseService] Auth updated; setting realtime auth (tokenLength=\(token.count))")
                    await client.realtimeV2.setAuth(token)
                    await client.realtimeV2.connect()
                }
            }
        }
    }
    
    // MARK: - Connection Testing
    
    /// Tests the Supabase connection by running a simple query
    /// - Returns: True if connection successful, false otherwise
    func testConnection() async -> Bool {
        do {
            let urlString = Secrets.supabaseURL
            AppLogger.network.debug("[SupabaseService] Testing Supabase connection...")
            AppLogger.network.debug("[SupabaseService] Deobfuscated URL: \(urlString)")
            AppLogger.network.debug("[SupabaseService] URL length: \(urlString.count)")
            
            // Verify URL is valid
            guard let url = URL(string: urlString), url.scheme == "https" else {
                AppLogger.network.error("[SupabaseService] Invalid URL format: \(urlString)")
                isConnected = false
                lastError = NSError(domain: "SupabaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL format"])
                return false
            }
            
            // Try to fetch profiles count as a simple connection test
            AppLogger.network.debug("[SupabaseService] Attempting to query profiles table...")
            let response = try await client
                .from("profiles")
                .select("id", head: true, count: .exact)
                .execute()
            
            // If we get a response (even if count is 0), connection works
            AppLogger.network.info("[SupabaseService] Connection successful! Response received.")
            isConnected = true
            lastError = nil
            return true
        } catch {
            isConnected = false
            lastError = error
            AppLogger.network.error("[SupabaseService] Connection test failed: \(error.localizedDescription)")
            
            // Check if it's a network error
            if let urlError = error as? URLError {
                AppLogger.network.error("[SupabaseService] URLError code: \(urlError.code.rawValue), description: \(urlError.localizedDescription)")
            }
            
            // Check if it's a Supabase-specific error
            if let nsError = error as NSError? {
                AppLogger.network.error("[SupabaseService] NSError domain: \(nsError.domain), code: \(nsError.code)")
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

