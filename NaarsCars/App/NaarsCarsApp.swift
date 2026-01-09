//
//  NaarsCarsApp.swift
//  NaarsCars
//
//  Created by Brendan Colford on 1/4/26.
//

import SwiftUI

@main
struct NaarsCarsApp: App {
    /// Global app state manager
    @StateObject private var appState = AppState()
    
    /// App delegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Initialize language preference on app launch
        LocalizationManager.shared.initializeLanguagePreference()
        
        // Test connection on app launch
        Task {
            let connected = await SupabaseService.shared.testConnection()
            print(connected ? "✅ Connected" : "❌ Failed")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    // Check authentication status on app launch
                    await appState.checkAuthStatus()
                }
        }
    }
}
