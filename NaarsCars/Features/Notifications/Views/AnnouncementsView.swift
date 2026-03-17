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
    @State private var viewModel: NotificationsListViewModel?
    let scrollToNotificationId: UUID?

    // SwiftData Query for local-first announcements
    @Query(sort: \SDNotification.createdAt, order: .reverse) private var sdNotifications: [SDNotification]

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    let announcements = getAnnouncements(viewModel: viewModel)

                    if viewModel.isLoading && announcements.isEmpty {
                        skeletonList
                    } else if let error = viewModel.error {
                        ErrorView(
                            error: error.localizedDescription,
                            retryAction: { Task { await viewModel.loadNotifications() } }
                        )
                    } else if announcements.isEmpty {
                        EmptyStateView(
                            icon: "megaphone.fill",
                            title: "notifications_no_announcements".localized,
                            message: "notifications_announcements_empty".localized,
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
                                        AppLogger.info("notifications", "[AnnouncementsView] Announcement tapped: \(notification.id)")
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
                } else {
                    skeletonList
                }
            }
            .navigationTitle("notifications_announcements_title".localized)
            .id("bell.announcements")
            .onDisappear { viewModel?.stop() }
        }
        .task {
            if viewModel == nil {
                let vm = NotificationsListViewModel()
                vm.setup(modelContext: modelContext)
                viewModel = vm
                await vm.loadNotifications()
            }
        }
    }

    private var skeletonList: some View {
        List {
            ForEach(0..<5) { _ in
                SkeletonNotificationRow()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    private func getAnnouncements(viewModel: NotificationsListViewModel) -> [AppNotification] {
        let all = viewModel.getFilteredNotifications(sdNotifications: sdNotifications)
        return all.filter { NotificationGrouping.announcementTypes.contains($0.type) }
    }
}

#Preview {
    AnnouncementsView(scrollToNotificationId: nil)
        .environment(AppState())
}
