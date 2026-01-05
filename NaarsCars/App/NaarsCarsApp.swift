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
    
    init() {
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
