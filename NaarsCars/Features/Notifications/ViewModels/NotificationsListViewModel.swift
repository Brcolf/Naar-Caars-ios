//
//  NotificationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for notifications list
//

import Foundation
import Observation
import SwiftData
internal import Combine

/// ViewModel for notifications list
@MainActor
@Observable final class NotificationsListViewModel {
    var isLoading: Bool = false
    /// The last load or refresh failed. The views keep their saved rows on screen and report
    /// this in a banner; only an empty screen shows the full error panel.
    var error: AppError?
    var unreadCount: Int = 0
    /// Unread rows that Mark All Read can clear. It leaves review requests and completion
    /// reminders alone, so the button is offered only while this is above zero.
    private(set) var markAllEligibleUnreadCount: Int = 0
    /// A failed mark-read or prompt lookup, shown in a banner over the list (which stays).
    var actionErrorMessage: String?
    /// Neutral notice for the inbox, such as why a reminder tap opened nothing.
    var noticeMessage: String?
    /// Row whose completion or review prompt is being looked up; the list shows progress on it.
    private(set) var checkingNotificationId: UUID?

    private var modelContext: ModelContext?
    private let notificationService: any NotificationServiceProtocol
    private let authService: any AuthServiceProtocol
    private let groupingManager: NotificationGroupingManager
    private let navigationRouter: NotificationNavigationRouter
    private let realtimeHandler: NotificationRealtimeHandler
    /// In-flight load/refresh task; cancelled in stop() and on next load to avoid use-after-free when view disappears.
    private var loadTask: Task<Void, Never>?
    /// Prompt lookups for completion and review rows. Built on first use so the initializer
    /// stays light (the announcements screen creates this view model too and never needs them).
    @ObservationIgnored private var completionPromptProvider: (any CompletionPromptProviding)?
    @ObservationIgnored private var reviewPromptProvider: (any ReviewPromptProviding)?
    /// In-flight prompt lookup for a tapped completion or review row; cancelled in stop().
    @ObservationIgnored private var actionCheckTask: Task<Void, Never>?

    init(
        notificationService: any NotificationServiceProtocol = NotificationService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        completionPromptProvider: (any CompletionPromptProviding)? = nil,
        reviewPromptProvider: (any ReviewPromptProviding)? = nil
    ) {
        self.notificationService = notificationService
        self.authService = authService
        self.completionPromptProvider = completionPromptProvider
        self.reviewPromptProvider = reviewPromptProvider
        groupingManager = NotificationGroupingManager()
        navigationRouter = NotificationNavigationRouter()
        realtimeHandler = NotificationRealtimeHandler()
        // Realtime subscription setup is deferred to setup(modelContext:) so that
        // throwaway instances (created by @State default evaluation during parent
        // body re-evaluation) stay lightweight and don't register observers.
        #if DEBUG
        print("[NotificationsListVM] init")
        #endif
    }

    deinit {
        #if DEBUG
        print("[NotificationsListVM] deinit")
        #endif
        // Cleanup is done in stop() from onDisappear. Do not start Task or touch MainActor state here (deinit is nonisolated).
    }

    /// Call from view onDisappear to cancel in-flight work and realtime subscription so VM can tear down safely.
    func stop() {
        AppLogger.info("notifications", "[NotificationsListVM] stop() called; cancelling loadTask and realtime observer")
        loadTask?.cancel()
        loadTask = nil
        cancelActionCheck()
        realtimeHandler.cancelAndRemoveObserver()
    }

    /// Set up the model context and realtime subscription.
    /// Called from .task — only runs for the VM that actually renders (not throwaway @State instances).
    /// Also called when the inbox list comes back on screen: opening the announcements list inside
    /// the sheet fires the list's onDisappear (stop()), so the observer is re-registered here (the
    /// handler registers once) and the unread counts are recomputed, since rows may have been
    /// read on the pushed screen.
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        realtimeHandler.setupRealtimeSubscription { [weak self] reason in
            await self?.handleRealtimeReload(reason: reason)
        }
        if let userId = authService.currentUserId {
            refreshUnreadCount(from: modelContext, userId: userId)
        }
    }

    /// Get filtered notifications from SwiftData models
    func getFilteredNotifications(sdNotifications: [SDNotification]) -> [AppNotification] {
        groupingManager.getFilteredNotifications(sdNotifications: sdNotifications)
    }

    /// Get notification groups from SwiftData models
    func getNotificationGroups(sdNotifications: [SDNotification]) -> [NotificationGroup] {
        groupingManager.getNotificationGroups(sdNotifications: sdNotifications)
    }

    /// Get precomputed grouped notifications (pinned + date-sectioned) for display
    func computeGroupedNotifications(sdNotifications: [SDNotification]) -> GroupedNotifications {
        groupingManager.computeGroupedNotifications(sdNotifications: sdNotifications)
    }

    /// Load notifications. Persistence is owned by `RefreshCoordinator` → `DashboardSyncEngine`
    /// (notifications are part of the `.dashboard` domain) → `BackgroundSyncActor`; the views'
    /// `@Query` re-renders and this method only recomputes `unreadCount` from SwiftData.
    func loadNotifications(forceRefresh: Bool = false) async {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            defer { loadTask = nil }
            guard !Task.isCancelled else { return }
            guard let userId = authService.currentUserId else {
                error = .notAuthenticated
                return
            }
            #if DEBUG
            print("[NotificationsListVM] loadNotifications start forceRefresh=\(forceRefresh)")
            #endif
            isLoading = true
            error = nil
            if let context = modelContext {
                refreshUnreadCount(from: context, userId: userId)
            }
            guard !Task.isCancelled else { isLoading = false; return }
            let result = await RefreshCoordinator.shared.forceFullRefreshAndWait(
                .dashboard,
                trigger: forceRefresh ? "pullToRefresh:notifications" : "manualReload:notifications"
            )
            guard !Task.isCancelled else { isLoading = false; return }
            if case .failed(let error, _)? = result {
                self.error = AppError.processingError(error.localizedDescription)
                AppLogger.error("notifications", "Error loading notifications: \(error.localizedDescription)")
            } else if let context = modelContext {
                refreshUnreadCount(from: context, userId: userId)
            }
            isLoading = false
            #if DEBUG
            print("[NotificationsListVM] loadNotifications end cancelled=\(Task.isCancelled)")
            #endif
        }
        await loadTask?.value
    }

    func refreshNotifications() async {
        await loadNotifications(forceRefresh: true)
    }

    /// Text for the non-blocking failure banner. A failed action always shows. A failed load or
    /// refresh shows here only while saved rows are on screen; an empty screen gets the full
    /// error panel instead.
    func failureBannerMessage(hasRows: Bool) -> String? {
        if let actionErrorMessage {
            return actionErrorMessage
        }
        return (error != nil && hasRows) ? "notifications_refresh_failed_banner".localized : nil
    }

    func dismissFailureBanner() {
        actionErrorMessage = nil
        error = nil
    }

    func markAsRead(_ notification: AppNotification) async {
        guard !notification.read else { return }

        actionErrorMessage = nil
        let flipped = markNotificationsReadLocally([notification.id])
        do {
            try await notificationService.markAsRead(notificationId: notification.id)
            if modelContext == nil {
                await loadNotifications()
            }
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationMarkedRead")
        } catch {
            // The list keeps its rows; a failed write is not a failed load, so `error` is untouched.
            restoreNotificationsUnreadLocally(flipped)
            actionErrorMessage = "notifications_mark_read_failed".localized
            AppLogger.error("notifications", "Error marking notification as read: \(error.localizedDescription)")
        }
    }

    /// - Returns: true when the server accepted the change. The caller shows its confirmation
    ///   only then; a failure is reported through `actionErrorMessage`.
    @discardableResult
    func markAllAsRead() async -> Bool {
        guard let userId = authService.currentUserId else { return false }

        actionErrorMessage = nil
        let flipped = markAllBellNotificationsReadLocally()
        do {
            try await notificationService.markAllBellNotificationsAsRead(userId: userId)
            if modelContext == nil {
                await loadNotifications()
            }
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationsMarkAllRead")
            return true
        } catch {
            restoreNotificationsUnreadLocally(flipped)
            actionErrorMessage = "notifications_mark_read_failed".localized
            AppLogger.error("notifications", "Error marking all notifications as read: \(error.localizedDescription)")
            return false
        }
    }

    /// Swipe action on an inbox row: marks every unread notification behind the row as read,
    /// including the review and completion types that a tap and Mark All Read leave alone.
    /// It is the way to clear a reminder whose request was already dealt with somewhere else.
    func markGroupAsReadExplicitly(_ group: NotificationGroup) async {
        let ids = group.notifications.filter { !$0.read }.map { $0.id }
        await markNotificationsRead(ids, badgeTrigger: "notificationSwipeMarkedRead")
    }

    /// Types that require explicit user action and should NOT be bulk-marked as read
    private static let bulkReadExcludedTypes: Set<NotificationType> = [
        .reviewRequest, .reviewReminder, .completionReminder
    ]

    /// Marks the rows read locally, then on the server. A rejected write puts the local flags
    /// back and reports the failure, so the rows, the unread count and the server agree.
    /// - Parameter badgeTrigger: nil when the caller has another write to make and refreshes the
    ///   badges itself after the last one. A badge refresh that follows another within the
    ///   debounce window is skipped, so an action refreshes once, after all of its writes.
    /// - Returns: false when the server rejected the write; true when it accepted it or there
    ///   was nothing to write.
    @discardableResult
    private func markNotificationsRead(_ ids: [UUID], badgeTrigger: String?) async -> Bool {
        guard !ids.isEmpty else { return true }
        actionErrorMessage = nil
        let flipped = markNotificationsReadLocally(ids)
        do {
            try await notificationService.markAsRead(notificationIds: ids)
        } catch {
            restoreNotificationsUnreadLocally(flipped)
            actionErrorMessage = "notifications_mark_read_failed".localized
            AppLogger.error("notifications", "Error marking notifications as read: \(error.localizedDescription)")
            return false
        }
        if modelContext == nil {
            await loadNotifications()
        }
        if let badgeTrigger {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: badgeTrigger)
        }
        return true
    }

    /// - Returns: ids of the rows this call changed from unread to read (what a roll-back restores)
    @discardableResult
    private func markAllBellNotificationsReadLocally() -> [UUID] {
        guard let context = modelContext, let userId = authService.currentUserId else { return [] }
        var flipped: [UUID] = []
        let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.userId == userId })
        if let notifications = try? context.fetch(fetchDescriptor) {
            for notification in notifications {
                guard let type = NotificationType(rawValue: notification.type),
                      !NotificationGrouping.messageTypes.contains(type),
                      !Self.bulkReadExcludedTypes.contains(type) else { continue }
                if !notification.read {
                    flipped.append(notification.id)
                }
                notification.read = true
            }
            try? context.save()
            refreshUnreadCount(from: context, userId: userId)
        }
        return flipped
    }

    /// - Returns: ids of the rows this call changed from unread to read (what a roll-back restores)
    @discardableResult
    private func markNotificationsReadLocally(_ ids: [UUID]) -> [UUID] {
        guard let context = modelContext, let userId = authService.currentUserId else { return [] }
        var flipped: [UUID] = []
        for id in ids {
            let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.id == id })
            if let notification = try? context.fetch(fetchDescriptor).first {
                if !notification.read {
                    flipped.append(id)
                }
                notification.read = true
            }
        }
        try? context.save()
        refreshUnreadCount(from: context, userId: userId)
        return flipped
    }

    /// Roll-back for a mark-read the server rejected: only the rows that call had changed go
    /// back to unread, so a row that was already read is never touched.
    private func restoreNotificationsUnreadLocally(_ ids: [UUID]) {
        guard !ids.isEmpty, let context = modelContext, let userId = authService.currentUserId else { return }
        for id in ids {
            let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.id == id })
            if let notification = try? context.fetch(fetchDescriptor).first {
                notification.read = false
            }
        }
        try? context.save()
        refreshUnreadCount(from: context, userId: userId)
    }

    private func refreshUnreadCount(from context: ModelContext, userId: UUID) {
        let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.userId == userId })
        if let notifications = try? context.fetch(fetchDescriptor) {
            let unread = getFilteredNotifications(sdNotifications: notifications).filter { !$0.read }
            let markAllEligible = unread.filter { !Self.bulkReadExcludedTypes.contains($0.type) }.count
            // Assign only on change: these are observed, and this also runs each time the list reappears.
            if unreadCount != unread.count {
                unreadCount = unread.count
            }
            if markAllEligibleUnreadCount != markAllEligible {
                markAllEligibleUnreadCount = markAllEligible
            }
        }
    }

    func handleNotificationTap(_ notification: AppNotification, group: NotificationGroup? = nil) {
        navigationRouter.handleNotificationTap(
            notification,
            group: group,
            markAsRead: { [weak self] tapped in
                Task { @MainActor [weak self] in
                    await self?.markAsRead(tapped)
                }
            },
            markGroupAsRead: { [weak self] tappedGroup in
                self?.markGroupAsRead(tappedGroup)
            }
        )
    }

    /// - Returns: true when the announcements list should open inside the inbox sheet (the
    ///   announcement has no linked Town Hall post); false when the tap left the inbox through a
    ///   deferred intent. One navigation per tap either way.
    @discardableResult
    func handleAnnouncementTap(_ notification: AppNotification) -> Bool {
        cancelActionCheck()
        return navigationRouter.handleAnnouncementTap(notification) { [weak self] tapped in
            Task { @MainActor [weak self] in
                await self?.markAsRead(tapped)
            }
        }
    }

    // MARK: - Completion and review rows

    /// Row tap from the inbox list.
    ///
    /// A completion reminder or a review request opens a prompt after the sheet has closed, and
    /// the prompt is only built while there is still something to answer. When there was not,
    /// the sheet closed onto nothing and the row stayed unread for good, because a tap and
    /// Mark All Read both skip these types. So the same lookup runs first, with the inbox still
    /// open: something to answer routes as before; nothing clears the request's rows and says
    /// why; a failed lookup says so and leaves the row alone. Every other row routes at once
    /// (a reminder or review row behind it is checked afterwards, in markGroupAsRead).
    func handleRowTap(_ notification: AppNotification, group: NotificationGroup?) {
        guard let kind = ActionRowKind(notification.type),
              let request = Self.linkedRequest(of: notification),
              let userId = authService.currentUserId else {
            // This tap routes now; a lookup still in flight must not route a second time after it.
            cancelActionCheck()
            handleNotificationTap(notification, group: group)
            return
        }
        // A second tap on the row that is already being looked up changes nothing.
        guard checkingNotificationId != notification.id else { return }

        cancelActionCheck()
        actionErrorMessage = nil
        checkingNotificationId = notification.id
        actionCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.lookUpPendingAction(
                kind,
                requestType: request.type,
                requestId: request.id,
                userId: userId
            )
            // Cancelled by stop() (the sheet went away) or by a newer tap, which owns the state now.
            guard !Task.isCancelled else { return }
            self.checkingNotificationId = nil
            self.actionCheckTask = nil
            switch result {
            case .pending:
                self.handleNotificationTap(notification, group: group)
            case .nothingToDo:
                await self.clearResolvedActionRows(
                    kind,
                    requestType: request.type,
                    requestId: request.id,
                    notification: notification,
                    group: group
                )
            case .failed:
                self.actionErrorMessage = "notifications_action_check_failed".localized
            }
        }
    }

    private func cancelActionCheck() {
        actionCheckTask?.cancel()
        actionCheckTask = nil
        if checkingNotificationId != nil {
            checkingNotificationId = nil
        }
    }

    private enum ActionRowKind {
        case completion
        case review

        init?(_ type: NotificationType) {
            switch type {
            case .completionReminder:
                self = .completion
            case .reviewRequest, .reviewReminder:
                self = .review
            default:
                return nil
            }
        }

        var notificationTypes: [NotificationType] {
            switch self {
            case .completion:
                return [.completionReminder]
            case .review:
                return [.reviewRequest, .reviewReminder]
            }
        }
    }

    private enum ActionLookupResult {
        case pending
        case nothingToDo
        case failed
    }

    private static func linkedRequest(of notification: AppNotification) -> (type: RequestType, id: UUID)? {
        if let rideId = notification.rideId {
            return (.ride, rideId)
        }
        if let favorId = notification.favorId {
            return (.favor, favorId)
        }
        return nil
    }

    /// Runs the lookup MainTabView's prompt path runs after the sheet closes (same providers),
    /// so "nothing to answer" here means that path would have shown nothing.
    private func lookUpPendingAction(
        _ kind: ActionRowKind,
        requestType: RequestType,
        requestId: UUID,
        userId: UUID
    ) async -> ActionLookupResult {
        do {
            switch kind {
            case .completion:
                let prompt = try await resolvedCompletionPromptProvider().fetchCompletionPrompt(
                    requestType: requestType,
                    requestId: requestId,
                    userId: userId
                )
                return prompt == nil ? .nothingToDo : .pending
            case .review:
                let prompt = try await resolvedReviewPromptProvider().fetchReviewPrompt(
                    requestType: requestType,
                    requestId: requestId,
                    userId: userId
                )
                return prompt == nil ? .nothingToDo : .pending
            }
        } catch {
            AppLogger.warning("notifications", "[NotificationsListVM] Prompt lookup failed for \(requestType.rawValue) \(requestId): \(error.localizedDescription)")
            return .failed
        }
    }

    private func resolvedCompletionPromptProvider() -> any CompletionPromptProviding {
        if let completionPromptProvider {
            return completionPromptProvider
        }
        let provider = CompletionPromptProvider()
        completionPromptProvider = provider
        return provider
    }

    private func resolvedReviewPromptProvider() -> any ReviewPromptProviding {
        if let reviewPromptProvider {
            return reviewPromptProvider
        }
        let provider = ReviewPromptProvider()
        reviewPromptProvider = provider
        return provider
    }

    /// Nothing is left to answer for this request: mark its reminder or review rows read, along
    /// with the group's ordinary rows as any tap does, tell the person why nothing opened, and
    /// then run the request-scoped call, which also reaches rows that are not in the local cache.
    private func clearResolvedActionRows(
        _ kind: ActionRowKind,
        requestType: RequestType,
        requestId: UUID,
        notification: AppNotification,
        group: NotificationGroup?
    ) async {
        let resolvedTypes = kind.notificationTypes
        let rows = group?.notifications ?? [notification]
        let resolvedIds = rows.filter { resolvedTypes.contains($0.type) && !$0.read }.map { $0.id }
        let ordinaryIds = rows.filter { shouldMarkReadOnTap($0.type) && !$0.read }.map { $0.id }

        // One write for both sets, through the path that reports a rejected write and puts the
        // rows back (the request-scoped call below cannot tell a failure from "nothing to
        // update"). The notice waits for it: the rows would otherwise read as cleared while the
        // server, the badge and the next sync still say unread.
        guard await markNotificationsRead(resolvedIds + ordinaryIds, badgeTrigger: nil) else { return }
        switch kind {
        case .completion:
            noticeMessage = "notifications_completion_no_longer_needed".localized
        case .review:
            noticeMessage = "notifications_review_no_longer_needed".localized
        }

        // In sequence, with one badge refresh after the last write (see markNotificationsRead).
        _ = await notificationService.markRequestScopedRead(
            requestType: requestType.rawValue,
            requestId: requestId,
            notificationTypes: resolvedTypes,
            includeReviews: false
        )
        _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationActionResolved")
    }

    private func markGroupAsRead(_ group: NotificationGroup) {
        let ordinaryIds = group.notifications.filter { shouldMarkReadOnTap($0.type) && !$0.read }.map { $0.id }
        let behind = actionRowBehindNewestRow(of: group)
        guard !ordinaryIds.isEmpty || behind != nil else { return }

        Task { @MainActor [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            guard let behind else {
                await self.markNotificationsRead(ordinaryIds, badgeTrigger: "notificationGroupMarkedRead")
                return
            }
            // The tap has already routed by the newest row and the sheet is closing, so the row
            // behind it is checked without a notice. This task is not the tracked lookup: stop()
            // must not cancel it. The badges refresh once, after the last write.
            let ordinaryWritten = await self.markNotificationsRead(ordinaryIds, badgeTrigger: nil)
            var needsBadgeRefresh = ordinaryWritten && !ordinaryIds.isEmpty
            let result = await self.lookUpPendingAction(
                behind.kind,
                requestType: behind.request.type,
                requestId: behind.request.id,
                userId: behind.userId
            )
            // Still something to answer, or the lookup failed: the row stays unread.
            if case .nothingToDo = result {
                let resolvedTypes = behind.kind.notificationTypes
                let resolvedIds = group.notifications.filter { resolvedTypes.contains($0.type) && !$0.read }.map { $0.id }
                if await self.markNotificationsRead(resolvedIds, badgeTrigger: nil) {
                    _ = await self.notificationService.markRequestScopedRead(
                        requestType: behind.request.type.rawValue,
                        requestId: behind.request.id,
                        notificationTypes: resolvedTypes,
                        includeReviews: false
                    )
                    needsBadgeRefresh = true
                }
            }
            if needsBadgeRefresh {
                _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationGroupMarkedRead")
            }
        }
    }

    /// A reminder or review row can sit unread behind a newer row of the same request. A tap
    /// routes by the newest row and leaves these types alone, so without a check the row would
    /// keep its unread styling, and the bell its count, after every tap.
    /// - Returns: what to look up, or nil when the newest row is itself a reminder or review row
    ///   (handleRowTap has looked that one up already) or nothing unread is waiting behind it.
    private func actionRowBehindNewestRow(
        of group: NotificationGroup
    ) -> (kind: ActionRowKind, request: (type: RequestType, id: UUID), userId: UUID)? {
        guard ActionRowKind(group.primaryNotification.type) == nil,
              let hidden = group.notifications.first(where: { !$0.read && ActionRowKind($0.type) != nil }),
              let kind = ActionRowKind(hidden.type),
              let request = Self.linkedRequest(of: hidden),
              let userId = authService.currentUserId else { return nil }
        return (kind: kind, request: request, userId: userId)
    }

    private func shouldMarkReadOnTap(_ type: NotificationType) -> Bool {
        switch type {
        case .reviewRequest, .reviewReminder, .completionReminder:
            return false
        default:
            return true
        }
    }

    /// Local-only reload used after `DashboardSyncEngine` posts `.notificationsDidSync`.
    ///
    /// `BackgroundSyncActor` has already written the fresh rows to SwiftData and the list itself
    /// is `@Query`-driven, so only the derived `unreadCount` needs recomputing. This must never
    /// hit the network: `RefreshCoordinator` is the single owner of refresh decisions.
    private func handleRealtimeReload(reason: String) async {
        AppLogger.info("notifications", "[NotificationsListVM] Coalesced local reload after sync: \(reason)")
        guard let context = modelContext, let userId = authService.currentUserId else { return }
        refreshUnreadCount(from: context, userId: userId)
    }
}
