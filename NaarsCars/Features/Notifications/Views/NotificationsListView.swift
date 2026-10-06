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
    @Environment(\.dismiss) private var dismiss
    // Optional to prevent throwaway VM creation: @State evaluates its default
    // on every parent body re-evaluation (unlike @StateObject's @autoclosure).
    // Since this view lives in a .sheet closure, the parent (MainTabView)
    // re-evaluates frequently. Lazy init in .task avoids the init/deinit storm.
    @State private var viewModel: NotificationsListViewModel?
    @State private var announcementNavigationTarget: AnnouncementNavigationTarget?
    @State private var toastMessage: String? = nil

    // SwiftData Query for "Zero-Spinner" experience
    @Query(sort: \SDNotification.createdAt, order: .reverse) private var sdNotifications: [SDNotification]

    var body: some View {
        NavigationStack {
            if let viewModel {
                let data = viewModel.computeGroupedNotifications(sdNotifications: sdNotifications)
                // One stable container for the modifiers below. Applied straight to the
                // conditional content they attach to each branch, so onDisappear (stop(), which
                // cancels the load in flight and drops its failure) would run on every switch
                // between skeleton, error, empty state and list, not only when the screen leaves.
                ZStack { content(viewModel: viewModel, data: data) }
                    .navigationTitle("notifications_title".localized)
                    .id("bell.notificationsList")
                    .toolbar {
                        // A visible way out; the sheet could only be closed by swiping down.
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common_done".localized) {
                                // Closing by hand: a row lookup still in flight must not
                                // route after the sheet has gone.
                                viewModel.stop()
                                dismiss()
                            }
                            .accessibilityIdentifier("bell.notificationsList.done")
                        }
                        // Offered only while it can clear something: Mark All Read leaves review
                        // requests and completion reminders, which are answered or swiped away.
                        if !data.isEmpty && viewModel.markAllEligibleUnreadCount > 0 {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("notifications_mark_all_read".localized) {
                                    HapticManager.lightImpact()
                                    Task {
                                        // A failure is reported by the banner; confirm only a real success.
                                        guard await viewModel.markAllAsRead() else { return }
                                        if viewModel.unreadCount == 0 {
                                            viewModel.noticeMessage = nil
                                            toastMessage = "notifications_all_caught_up".localized
                                        } else {
                                            toastMessage = nil
                                            viewModel.noticeMessage = "notifications_mark_all_read_action_remaining".localized
                                        }
                                    }
                                }
                                .font(.naarsBody)
                                .id("bell.notificationsList.markAllRead")
                            }
                        }
                    }
                    .navigationDestination(item: $announcementNavigationTarget) { target in
                        AnnouncementsView(scrollToNotificationId: target.id)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .dismissNotificationsSurface)) { _ in
                        AppLogger.info("notifications", "[NotificationsListView] Dismissing notifications surface")
                        if case .notifications = NavigationCoordinator.shared.pendingIntent {
                            NavigationCoordinator.shared.pendingIntent = nil
                        }
                        dismiss()
                    }
                    // Also the way back from the announcements list pushed inside this sheet: that
                    // push fires onDisappear below, so the sync observer is re-registered and the
                    // unread counts recomputed here.
                    .onAppear { viewModel.setup(modelContext: modelContext) }
                    .onDisappear { viewModel.stop() }
                    .onChange(of: viewModel.noticeMessage) { _, notice in
                        // One toast at a time: both sit at the top edge.
                        if notice != nil {
                            toastMessage = nil
                        }
                    }
                    .toast(message: $toastMessage)
                    .toast(message: noticeBinding(viewModel), style: .info)
                    // A failed refresh or mark-read keeps the saved rows on screen.
                    .errorBanner(message: failureBannerBinding(viewModel, hasRows: !data.isEmpty))
            } else {
                List {
                    ForEach(0..<5) { _ in
                        SkeletonNotificationRow()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.naarsBackground)
                .navigationTitle("notifications_title".localized)
            }
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
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func content(viewModel: NotificationsListViewModel, data: GroupedNotifications) -> some View {
        if viewModel.isLoading && data.isEmpty {
            List {
                ForEach(0..<5) { _ in
                    SkeletonNotificationRow()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.naarsBackground)
            .accessibilityLabel("notifications_loading_accessibility".localized)
        } else if let error = viewModel.error, data.isEmpty {
            // Full error panel only when there is nothing to show. With saved rows on screen
            // the failure is reported by the banner and the list stays.
            ErrorView(
                error: error.localizedDescription,
                retryAction: { Task { await viewModel.loadNotifications() } }
            )
        } else if data.isEmpty {
            EmptyStateView(
                icon: "bell.fill",
                title: "notifications_no_notifications".localized,
                message: "notifications_all_caught_up".localized,
                actionTitle: nil,
                action: nil
            )
        } else {
            notificationsList(viewModel: viewModel, data: data)
        }
    }
    
    @ViewBuilder
    private func notificationsList(viewModel: NotificationsListViewModel, data: GroupedNotifications) -> some View {
        List {
            if !data.pinned.isEmpty {
                Section {
                    ForEach(data.pinned) { group in
                        notificationRow(viewModel: viewModel, for: group)
                    }
                }
            }

            ForEach(data.sections, id: \.date) { section in
                Section(header: Text(dayString(section.date))) {
                    ForEach(section.groups) { group in
                        notificationRow(viewModel: viewModel, for: group)
                    }
                }
            }

            // Archived-notification hint
            Section {
                Text("notifications_archived_hint".localized)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
        .refreshable { await viewModel.refreshNotifications() }
    }

    @ViewBuilder
    private func notificationRow(viewModel: NotificationsListViewModel, for group: NotificationGroup) -> some View {
        // A completion or review row is looked up before it routes; show that on the row.
        let isCheckingAction = viewModel.checkingNotificationId == group.primaryNotification.id
        NotificationRow(
            notification: group.primaryNotification,
            isReadOverride: !group.hasUnread,
            groupCount: group.totalCount
        ) {
            if NotificationGrouping.announcementTypes.contains(group.primaryNotification.type) {
                AppLogger.info("notifications", "[NotificationsListView] Notification tapped type=announcement id=\(group.primaryNotification.id)")
                // One navigation per tap. A broadcast with a linked post leaves the inbox for
                // Town Hall (deferred intent, the sheet closes); any other announcement opens
                // the announcements list inside this sheet.
                if viewModel.handleAnnouncementTap(group.primaryNotification) {
                    announcementNavigationTarget = .init(id: group.primaryNotification.id)
                }
            } else {
                AppLogger.info("notifications", "[NotificationsListView] Notification tapped type=\(group.primaryNotification.type.rawValue) id=\(group.primaryNotification.id)")
                viewModel.handleRowTap(group.primaryNotification, group: group)
            }
        }
        .opacity(isCheckingAction ? 0.5 : 1)
        .overlay {
            if isCheckingAction {
                ProgressView()
                    .accessibilityLabel("common_loading".localized)
            }
        }
        .id("bell.notificationsList.row(\(group.primaryNotification.id))")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        // Every unread row can be cleared by hand, including the review and completion rows
        // that a tap and Mark All Read leave alone.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if group.hasUnread {
                Button {
                    Task { await viewModel.markGroupAsReadExplicitly(group) }
                } label: {
                    Label("notifications_action_mark_read".localized, systemImage: "envelope.open")
                }
                .tint(Color.naarsPrimary)
                .accessibilityIdentifier("bell.notificationsList.row.markRead")
            }
        }
    }

    // MARK: - Helpers

    /// Info toast fed by the view model: why a reminder tap opened nothing, or what Mark All Read left.
    private func noticeBinding(_ viewModel: NotificationsListViewModel) -> Binding<String?> {
        // Read during the body pass so the view is re-evaluated when the notice changes; the
        // getter stays live because the toast compares against the current value when it expires.
        _ = viewModel.noticeMessage
        return Binding(
            get: { viewModel.noticeMessage },
            set: { viewModel.noticeMessage = $0 }
        )
    }

    /// Failure banner over the list. While a toast is up the banner steps aside (both sit at the
    /// top edge) and comes back once the toast has gone.
    private func failureBannerBinding(_ viewModel: NotificationsListViewModel, hasRows: Bool) -> Binding<String?> {
        let message = (toastMessage == nil && viewModel.noticeMessage == nil)
            ? viewModel.failureBannerMessage(hasRows: hasRows)
            : nil
        return Binding(
            get: { message },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissFailureBanner()
                }
            }
        )
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            return "notifications_today".localized
        } else if Calendar.current.isDateInYesterday(date) {
            return "notifications_yesterday".localized
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
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
                RoundedRectangle(cornerRadius: Constants.Radius.xs)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 16)
                
                RoundedRectangle(cornerRadius: Constants.Radius.xs)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 12)
                
                RoundedRectangle(cornerRadius: Constants.Radius.xs)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 10)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.card)
        .cardShadow()
    }
}

#Preview {
    NotificationsListView()
        .environment(AppState())
}




