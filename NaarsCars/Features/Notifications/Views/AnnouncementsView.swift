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
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: NotificationsListViewModel?
    let scrollToNotificationId: UUID?
    /// True where this screen is the root of a sheet, which has no Back button to leave by
    var showsCloseButton: Bool = false

    // SwiftData Query for local-first announcements
    @Query(sort: \SDNotification.createdAt, order: .reverse) private var sdNotifications: [SDNotification]

    // No NavigationStack here: the notifications list pushes this screen onto its own stack,
    // and a second stack drew a second navigation bar. The sheet in MainTabView wraps it in one.
    var body: some View {
        // A ZStack, not a Group: a Group hands the modifiers below to each branch of its content,
        // so onDisappear (stop(), which cancels the load in flight and drops its failure) and
        // .task would run again on every switch between skeleton, error, empty state and list.
        ZStack {
            if let viewModel {
                let announcements = getAnnouncements(viewModel: viewModel)

                if viewModel.isLoading && announcements.isEmpty {
                    skeletonList
                } else if let error = viewModel.error, announcements.isEmpty {
                    // Full error panel only when there is nothing to show; with saved
                    // announcements on screen the banner below reports the failure.
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
                    // A failed refresh or mark-read keeps the saved announcements on screen.
                    .errorBanner(message: failureBannerBinding(viewModel))
                }
            } else {
                skeletonList
            }
        }
        .navigationTitle("notifications_announcements_title".localized)
        .id("bell.announcements")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_close".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("bell.announcements.close")
                }
            }
        }
        .onDisappear { viewModel?.stop() }
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

    /// Failure banner over the list (only attached while announcements are on screen).
    private func failureBannerBinding(_ viewModel: NotificationsListViewModel) -> Binding<String?> {
        // Computed during the body pass so the view is re-evaluated when the failure changes.
        let message = viewModel.failureBannerMessage(hasRows: true)
        return Binding(
            get: { message },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissFailureBanner()
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        AnnouncementsView(scrollToNotificationId: nil, showsCloseButton: true)
    }
    .environment(AppState())
}
