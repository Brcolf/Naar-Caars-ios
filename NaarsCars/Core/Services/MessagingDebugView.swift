//
//  MessagingDebugView.swift
//  NaarsCars
//
//  Debug view for inspecting messaging system state
//  Useful for troubleshooting loading issues, race conditions, and cache state
//

import SwiftUI
internal import Combine

/// Debug view for messaging system inspection
struct MessagingDebugView: View {
    @StateObject private var viewModel: MessagingDebugViewModel
    @State private var showingOperations = false
    @State private var showingCacheStats = false
    
    init(conversationViewModel: ConversationsListViewModel) {
        _viewModel = StateObject(wrappedValue: MessagingDebugViewModel(conversationViewModel: conversationViewModel))
    }
    
    var body: some View {
        List {
            Section("System Status") {
                InfoRow(label: "Total Operations", value: "\(viewModel.totalOperations)")
                InfoRow(label: "Active Operations", value: "\(viewModel.activeOperationsCount)")
                InfoRow(label: "Cache Hit Rate", value: viewModel.cacheHitRate)
                
                Button {
                    showingOperations = true
                } label: {
                    HStack {
                        Text("View Active Operations")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("Conversations") {
                InfoRow(label: "Loaded", value: "\(viewModel.conversationsCount)")
                InfoRow(label: "Is Loading", value: viewModel.isLoading ? "Yes" : "No")
                InfoRow(label: "Is Loading More", value: viewModel.isLoadingMore ? "Yes" : "No")
                InfoRow(label: "Has More", value: viewModel.hasMore ? "Yes" : "No")
                InfoRow(label: "Load Attempts", value: "\(viewModel.loadAttempts)")
                
                if let error = viewModel.error {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Section("Cache Status") {
                Button {
                    showingCacheStats = true
                } label: {
                    HStack {
                        Text("View Cache Details")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Clear Display Name Cache") {
                    Task {
                        await viewModel.clearDisplayNameCache()
                    }
                }
                .foregroundColor(.orange)
            }
            
            Section("Actions") {
                Button("Refresh Data") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .foregroundColor(.blue)
                
                Button("Reset Statistics") {
                    Task {
                        await viewModel.resetStatistics()
                    }
                }
                .foregroundColor(.orange)
                
                Button("Export Debug Log") {
                    viewModel.exportDebugLog()
                }
                .foregroundColor(.green)
            }
            
            Section("Race Condition Detection") {
                if viewModel.potentialRaceConditions.isEmpty {
                    Text("No race conditions detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.potentialRaceConditions, id: \.self) { warning in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(warning)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Messaging Debug")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showingOperations) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(viewModel.activeOperationsSummary)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                }
                .navigationTitle("Active Operations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingOperations = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCacheStats) {
            NavigationStack {
                List {
                    Section("Display Name Cache") {
                        InfoRow(label: "Cached Names", value: "\(viewModel.cachedDisplayNamesCount)")
                    }
                    
                    Section("Message/Conversation Cache") {
                        Text("Cache details managed by CacheManager")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .navigationTitle("Cache Statistics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingCacheStats = false
                        }
                    }
                }
            }
        }
    }
}

/// Simple info row for key-value display
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

/// ViewModel for debug view
@MainActor
final class MessagingDebugViewModel: ObservableObject {
    @Published var totalOperations: Int = 0
    @Published var activeOperationsCount: Int = 0
    @Published var cacheHitRate: String = "N/A"
    @Published var conversationsCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMore: Bool = false
    @Published var loadAttempts: Int = 0
    @Published var error: String?
    @Published var activeOperationsSummary: String = ""
    @Published var cachedDisplayNamesCount: Int = 0
    @Published var potentialRaceConditions: [String] = []
    
    private let conversationViewModel: ConversationsListViewModel
    private let logger = MessagingLogger.shared
    
    init(conversationViewModel: ConversationsListViewModel) {
        self.conversationViewModel = conversationViewModel
    }
    
    func loadData() async {
        await refresh()
    }
    
    func refresh() async {
        // Get logger statistics
        let stats = await logger.getOperationStatistics()
        totalOperations = stats.values.reduce(0, +)
        
        // Get active operations summary
        activeOperationsSummary = await logger.getActiveOperationsSummary()
        
        // Count active operations
        activeOperationsCount = activeOperationsSummary.components(separatedBy: "\n").count - 1
        if activeOperationsCount < 0 { activeOperationsCount = 0 }
        
        // Get conversation view model state
        let debugInfo = await conversationViewModel.getDebugInfo()
        conversationsCount = conversationViewModel.conversations.count
        isLoading = conversationViewModel.isLoading
        isLoadingMore = conversationViewModel.isLoadingMore
        hasMore = conversationViewModel.hasMoreConversations
        error = conversationViewModel.error?.localizedDescription
        
        // Get display name cache count
        let cachedIds = await ConversationDisplayNameCache.shared.getCachedConversationIds()
        cachedDisplayNamesCount = cachedIds.count
        
        // Parse race condition warnings from debug info
        potentialRaceConditions = debugInfo.components(separatedBy: "\n")
            .filter { $0.contains("RACE CONDITION") }
    }
    
    func resetStatistics() async {
        await logger.resetStatistics()
        await refresh()
    }
    
    func clearDisplayNameCache() async {
        await ConversationDisplayNameCache.shared.clearAll()
        await refresh()
    }
    
    func exportDebugLog() {
        Task {
            let debugInfo = await conversationViewModel.getDebugInfo()
            let stats = await logger.getOperationStatistics()
            let operations = await logger.getActiveOperationsSummary()
            
            let fullLog = """
            ===== MESSAGING DEBUG LOG =====
            Generated: \(Date())
            
            \(debugInfo)
            
            === Operation Statistics ===
            \(stats.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
            
            === Active Operations ===
            \(operations)
            
            ===== END DEBUG LOG =====
            """
            
            // Copy to clipboard
            #if os(iOS)
            UIPasteboard.general.string = fullLog
            #endif
            
            print(fullLog)
            
            // In a real app, you might want to share this via share sheet
            // or save to a file
        }
    }
}

#Preview {
    NavigationStack {
        MessagingDebugView(conversationViewModel: ConversationsListViewModel())
    }
}
