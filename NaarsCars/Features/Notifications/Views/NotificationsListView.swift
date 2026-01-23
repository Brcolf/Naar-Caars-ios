//
//  NotificationsListView.swift
//  NaarsCars
//
//  Notifications list view
//

import SwiftUI
import SwiftData

/// Notifications list view for displaying in-app notifications
struct NotificationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = NotificationsListViewModel()
    @EnvironmentObject var appState: AppState
    @State private var announcementNavigationTarget: AnnouncementNavigationTarget?
    
    // SwiftData Query for "Zero-Spinner" experience
    @Query(sort: \SDNotification.createdAt, order: .reverse) private var sdNotifications: [SDNotification]
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Notifications")
                .id("bell.notificationsList")
                .toolbar {
                    if !viewModel.getNotificationGroups(sdNotifications: sdNotifications).isEmpty && viewModel.unreadCount > 0 {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Mark All Read") {
                                Task { await viewModel.markAllAsRead() }
                            }
                            .font(.naarsBody)
                            .id("bell.notificationsList.markAllRead")
                        }
                    }
                }
                .task {
                    viewModel.setup(modelContext: modelContext)
                    await viewModel.loadNotifications()
                }
                .navigationDestination(item: $announcementNavigationTarget) { target in
                    AnnouncementsView(scrollToNotificationId: target.id)
                }
                .onReceive(NotificationCenter.default.publisher(for: .dismissNotificationsSurface)) { _ in
                    print("🔔 [NotificationsListView] Dismissing notifications surface")
                    NotificationCenter.default.post(name: NSNotification.Name("dismissNotificationsSheet"), object: nil)
                }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var content: some View {
        let groups = viewModel.getNotificationGroups(sdNotifications: sdNotifications)
        
        if viewModel.isLoading && groups.isEmpty {
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
        } else if groups.isEmpty {
            EmptyStateView(
                icon: "bell.fill",
                title: "No Notifications",
                message: "You're all caught up! New notifications will appear here.",
                actionTitle: nil,
                action: nil
            )
        } else {
            notificationsList(groups: groups)
        }
    }
    
    @ViewBuilder
    private func notificationsList(groups: [NotificationGroup]) -> some View {
        List {
            let pinned = groups.filter { $0.isPinned }
            let regular = groups.filter { !$0.isPinned }
            let grouped = Dictionary(grouping: regular) { group in
                Calendar.current.startOfDay(for: group.primaryNotification.createdAt)
            }
            
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { group in
                        notificationRow(for: group)
                    }
                }
            }
            
            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                Section(header: Text(dayString(day))) {
                    ForEach(grouped[day] ?? []) { group in
                        notificationRow(for: group)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refreshNotifications() }
    }
    
    @ViewBuilder
    private func notificationRow(for group: NotificationGroup) -> some View {
        NotificationRow(
            notification: group.primaryNotification,
            isReadOverride: !group.hasUnread,
            groupCount: group.totalCount
        ) {
            if NotificationGrouping.announcementTypes.contains(group.primaryNotification.type) {
                viewModel.handleAnnouncementTap(group.primaryNotification)
                announcementNavigationTarget = .init(id: group.primaryNotification.id)
            } else {
                viewModel.handleNotificationTap(group.primaryNotification, group: group)
            }
        }
        .id("bell.notificationsList.row(\(group.primaryNotification.id))")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

private struct AnnouncementNavigationTarget: Identifiable, Hashable {
    let id: UUID
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





