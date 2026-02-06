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
    
    /// SwiftData container (nil when initialization fails)
    @State private var container: ModelContainer?
    
    /// Whether to show the data-error recovery alert
    @State private var showDataError = false
    
    init() {
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Initialize language preference on app launch
        LocalizationManager.shared.initializeLanguagePreference()
        
        // Apply saved theme preference on app launch
        ThemeManager.shared.applyThemeOnLaunch()
        
        // Initialize SwiftData with migration plan
        do {
            let newContainer = try Self.createModelContainer()
            _container = State(initialValue: newContainer)
            Self.setupSyncEngines(with: newContainer)
        } catch {
            AppLogger.error("app", "Failed to initialize SwiftData container: \(error)")
            _container = State(initialValue: nil)
            _showDataError = State(initialValue: true)
        }
        
        // Test connection on app launch
        Task {
            let connected = await SupabaseService.shared.testConnection()
            AppLogger.info("app", connected ? "Supabase connected" : "Supabase connection failed")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
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
                } else {
                    // Placeholder while the data-error alert is presented
                    Color(.systemBackground)
                }
            }
            .alert("Data Error", isPresented: $showDataError) {
                Button("Clear Local Data", role: .destructive) {
                    clearLocalDataAndRetry()
                }
                Button("Quit", role: .cancel) { }
            } message: {
                Text("The local data store could not be loaded. You can clear local data and try again, or quit the app.")
            }
        }
    }
    
    // MARK: - SwiftData Helpers
    
    /// Creates a ModelContainer using the versioned schema and migration plan.
    private static func createModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: NaarsCarsModelMigrationPlan.self
        )
    }
    
    /// Wires up all sync engines and repositories with the given container's main context.
    private static func setupSyncEngines(with container: ModelContainer) {
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
    }
    
    /// Deletes the SwiftData store files and attempts to recreate the container.
    private func clearLocalDataAndRetry() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        // Remove the SQLite store and its journal files
        let storeFiles = ["default.store", "default.store-wal", "default.store-shm"]
        for file in storeFiles {
            let url = appSupport.appendingPathComponent(file)
            try? fileManager.removeItem(at: url)
        }
        
        // Retry container creation
        do {
            let newContainer = try Self.createModelContainer()
            container = newContainer
            Self.setupSyncEngines(with: newContainer)
        } catch {
            AppLogger.error("app", "Failed to reinitialize SwiftData container after clearing data: \(error)")
            showDataError = true
        }
    }
}
