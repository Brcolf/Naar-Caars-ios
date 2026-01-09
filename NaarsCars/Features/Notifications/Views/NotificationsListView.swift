//
//  NotificationsListView.swift
//  NaarsCars
//
//  Notifications list view
//

import SwiftUI

/// Notifications list view for displaying in-app notifications
struct NotificationsListView: View {
    @StateObject private var viewModel = NotificationsListViewModel()
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    // Skeleton loading
                    List {
                        ForEach(0..<5) { _ in
                            SkeletonNotificationRow()
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error.localizedDescription,
                        retryAction: { Task { await viewModel.loadNotifications() } }
                    )
                } else if viewModel.notifications.isEmpty {
                    EmptyStateView(
                        icon: "bell.fill",
                        title: "No Notifications",
                        message: "You're all caught up! New notifications will appear here.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    List {
                        // Pinned notifications first
                        if !pinnedNotifications.isEmpty {
                            Section {
                                ForEach(pinnedNotifications) { notification in
                                    NotificationRow(notification: notification) {
                                        viewModel.handleNotificationTap(notification)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                        
                        // Grouped by day
                        ForEach(groupedNotifications.keys.sorted(by: >), id: \.self) { day in
                            Section(header: Text(dayString(day))) {
                                ForEach(groupedNotifications[day] ?? []) { notification in
                                    NotificationRow(notification: notification) {
                                        viewModel.handleNotificationTap(notification)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refreshNotifications()
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if !viewModel.notifications.isEmpty && viewModel.unreadCount > 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Mark All Read") {
                            Task {
                                await viewModel.markAllAsRead()
                            }
                        }
                        .font(.naarsBody)
                    }
                }
            }
            .task {
                await viewModel.loadNotifications()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var pinnedNotifications: [AppNotification] {
        viewModel.notifications.filter { $0.pinned }
    }
    
    private var regularNotifications: [AppNotification] {
        viewModel.notifications.filter { !$0.pinned }
    }
    
    private var groupedNotifications: [Date: [AppNotification]] {
        Dictionary(grouping: regularNotifications) { notification in
            Calendar.current.startOfDay(for: notification.createdAt)
        }
    }
    
    // MARK: - Helpers
    
    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

/// Skeleton loading row for notifications
struct SkeletonNotificationRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 10)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    NotificationsListView()
        .environmentObject(AppState())
}




