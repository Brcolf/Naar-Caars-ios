//
//  NaarsCarsApp.swift
//  NaarsCars
//
//  Created by Brendan Colford on 1/4/26.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct NaarsCarsApp: App {
    /// Global app state manager
    @StateObject private var appState = AppState()
    
    /// Theme manager for dark mode support
    @StateObject private var themeManager = ThemeManager.shared
    
    /// App delegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// SwiftData container
    let container: ModelContainer
    
    init() {
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Initialize language preference on app launch
        LocalizationManager.shared.initializeLanguagePreference()
        
        // Apply saved theme preference on app launch
        ThemeManager.shared.applyThemeOnLaunch()
        
        // Initialize SwiftData
        do {
            container = try ModelContainer(
                for: SDConversation.self,
                SDMessage.self,
                SDRide.self,
                SDFavor.self,
                SDNotification.self,
                SDTownHallPost.self,
                SDTownHallComment.self
            )
            
            // Setup Sync Engines with the model context
            let context = container.mainContext
            MessagingRepository.shared.setup(modelContext: context)
            NotificationRepository.shared.setup(modelContext: context)
            DashboardSyncEngine.shared.setup(modelContext: context)
            MessagingSyncEngine.shared.setup(modelContext: context) 
            TownHallRepository.shared.setup(modelContext: context)
            TownHallSyncEngine.shared.setup(modelContext: context)
            
            // Start background sync
            DashboardSyncEngine.shared.startSync()
            MessagingSyncEngine.shared.startSync()
            TownHallSyncEngine.shared.startSync()
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
        
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
                .modelContainer(container)
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
