//
//  AnnouncementsView.swift
//  NaarsCars
//
//  Dedicated announcements list view
//

import SwiftUI
import SwiftData

struct AnnouncementsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = NotificationsListViewModel()
    @EnvironmentObject var appState: AppState
    let scrollToNotificationId: UUID?
    
    // SwiftData Query for local-first announcements
    @Query(sort: \SDNotification.createdAt, order: .reverse) private var sdNotifications: [SDNotification]

    var body: some View {
        NavigationStack {
            Group {
                let announcements = getAnnouncements()
                
                if viewModel.isLoading && announcements.isEmpty {
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
                } else if announcements.isEmpty {
                    EmptyStateView(
                        icon: "megaphone.fill",
                        title: "No Announcements",
                        message: "Announcements will appear here when available.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(announcements) { notification in
                                NotificationRow(notification: notification) {
                                    Task {
                                        await viewModel.markAsRead(notification)
                                    }
                                    print("📣 [AnnouncementsView] Announcement tapped: \(notification.id)")
                                }
                                .id("bell.announcements.row(\(notification.id))")
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .onAppear {
                            if let scrollToNotificationId {
                                let anchorId = "bell.announcements.row(\(scrollToNotificationId))"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation {
                                        proxy.scrollTo(anchorId, anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Announcements")
            .id("bell.announcements")
            .task {
                viewModel.setup(modelContext: modelContext)
                await viewModel.loadNotifications()
            }
        }
    }

    private func getAnnouncements() -> [AppNotification] {
        let all = viewModel.getFilteredNotifications(sdNotifications: sdNotifications)
        return all.filter { NotificationGrouping.announcementTypes.contains($0.type) }
    }
}

#Preview {
    AnnouncementsView(scrollToNotificationId: nil)
        .environmentObject(AppState())
}

