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
    
    /// Theme manager for dark mode support
    @StateObject private var themeManager = ThemeManager.shared
    
    /// App delegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Initialize language preference on app launch
        LocalizationManager.shared.initializeLanguagePreference()
        
        // Apply saved theme preference on app launch
        ThemeManager.shared.applyThemeOnLaunch()
        
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
                .environmentObject(themeManager)
                .task {
                    // Check authentication status on app launch
                    await appState.checkAuthStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Re-apply theme when app becomes active (handles system theme changes)
                    themeManager.applyTheme()
                }
        }
    }
}
