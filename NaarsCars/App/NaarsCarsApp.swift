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
    @State private var appState = AppState()
    
    /// Theme manager for dark mode support
    @State private var themeManager = ThemeManager.shared
    
    /// App delegate for push notification handling
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// SwiftData container (nil when initialization fails)
    @State private var container: ModelContainer?
    
    /// Whether to show the data-error recovery alert
    @State private var showDataError = false
    
    init() {
        let appInitStart = Date()
        var containerReady = false
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
            containerReady = true
        } catch {
            AppLogger.error("app", "SwiftData container failed, attempting auto-recovery: \(error)")
            // Auto-clear corrupt/incompatible store and retry
            Self.deleteStoreFiles()
            do {
                let recovered = try Self.createModelContainer()
                _container = State(initialValue: recovered)
                Self.setupSyncEngines(with: recovered)
                containerReady = true
                AppLogger.info("app", "SwiftData container recovered after clearing local cache")
            } catch {
                AppLogger.error("app", "Failed to initialize SwiftData container after recovery: \(error)")
                _container = State(initialValue: nil)
                _showDataError = State(initialValue: true)
            }
        }
        
        // Connection test removed — unnecessary network round-trip during init.
        // Auth session check in performCriticalLaunch() validates connectivity.

        Task {
            await PerformanceMonitor.shared.record(
                operation: "launch.appInit",
                duration: Date().timeIntervalSince(appInitStart),
                metadata: ["containerReady": containerReady]
            )
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .environment(appState)
                        .environment(themeManager)
                        .modelContainer(container)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            // Re-apply theme when app becomes active (handles system theme changes)
                            themeManager.applyTheme()
                        }
                } else {
                    // Placeholder while the data-error alert is presented
                    Color(.systemBackground)
                }
            }
            .alert("app_data_error_title".localized, isPresented: $showDataError) {
                Button("app_clear_local_data".localized, role: .destructive) {
                    clearLocalDataAndRetry()
                }
            } message: {
                Text("app_data_error_message".localized)
            }
        }
    }
    
    // MARK: - SwiftData Helpers
    
    /// Creates a ModelContainer for all SwiftData models.
    /// Uses unversioned schema — SwiftData handles additive property changes
    /// (e.g. new columns with defaults) via automatic lightweight migration.
    private static func createModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SDConversation.self, SDMessage.self,
                 SDDeletedMessage.self,
                 SDRide.self, SDFavor.self,
                 SDNotification.self,
                 SDTownHallPost.self, SDTownHallComment.self
        )
    }
    
    /// Wires up all sync engines and repositories with the given container's main context.
    private static func setupSyncEngines(with container: ModelContainer) {
        let setupStart = Date()
        let context = container.mainContext
        MessagingRepository.shared.setup(modelContext: context)
        NotificationRepository.shared.setup(modelContext: context)
        TownHallRepository.shared.setup(modelContext: context)
        SyncEngineOrchestrator.shared.register(MessagingSyncEngine.shared)
        SyncEngineOrchestrator.shared.register(DashboardSyncEngine.shared)
        SyncEngineOrchestrator.shared.register(TownHallSyncEngine.shared)
        SyncEngineOrchestrator.shared.setupAll(modelContext: context)
        DashboardSyncEngine.shared.setupBackgroundActor(container: container)
        MessagingSyncEngine.shared.setupBackgroundActor(container: container)

        // Sync engines are intentionally started after first interactive launch state
        // in AppLaunchManager.performDeferredLoading(userId:) to keep startup lean.
        Task {
            await PerformanceMonitor.shared.record(
                operation: "launch.syncEngineSetup",
                duration: Date().timeIntervalSince(setupStart)
            )
        }
    }
    
    /// Deletes the SQLite store files. Safe to call from init (static, no instance state).
    private static func deleteStoreFiles() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for file in ["default.store", "default.store-wal", "default.store-shm"] {
            try? fileManager.removeItem(at: appSupport.appendingPathComponent(file))
        }
    }

    /// Deletes the SwiftData store files and attempts to recreate the container.
    private func clearLocalDataAndRetry() {
        Self.deleteStoreFiles()

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
