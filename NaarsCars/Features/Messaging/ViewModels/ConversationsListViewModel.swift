//
//  ConversationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for conversations list
//

import Foundation
import SwiftUI
internal import Combine

/// Result of a message search across conversations
struct MessageSearchResult: Identifiable {
    let id: UUID
    let message: Message
    let conversationId: UUID
    let conversationTitle: String
    
    init(message: Message, conversationId: UUID, conversationTitle: String) {
        self.id = message.id
        self.message = message
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
    }
}

/// ViewModel for conversations list
@MainActor
@Observable final class ConversationsListViewModel {
    var conversations: [ConversationWithDetails] = [] {
        didSet { recomputeFilteredConversations() }
    }
    private(set) var filteredConversations: [ConversationWithDetails] = []
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMoreConversations: Bool = true
    var error: AppError?

    // MARK: - Search State
    var searchText: String = "" {
        didSet {
            recomputeFilteredConversations()
            scheduleSearchDebounce()
        }
    }
    var searchResults: [MessageSearchResult] = []
    var isSearching: Bool = false
    /// Conversations the current user has muted (push suppressed); drives the row's bell icon
    var mutedConversations: Set<UUID> = []
    
    private let conversationService: any ConversationServiceProtocol
    private let profileService: any ProfileServiceProtocol
    private let messageService: any MessageServiceProtocol
    private let repository = MessagingRepository.shared
    private let authService: any AuthServiceProtocol
    private let muteService = ConversationMuteService.shared
    private let participantService = ConversationParticipantService.shared
    private var cancellables = Set<AnyCancellable>()
#if DEBUG
    /// Test hook: number of Combine subscriptions installed by `start()`.
    var debugObservationSinkCount: Int { cancellables.count }
#endif
    private let pageSize = 10
    private var currentOffset = 0
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    /// Coalesced participant-profile hydration for conversations the local publisher
    /// surfaced without `otherParticipants` (the coordinator path stores IDs only).
    private var hydrationTask: Task<Void, Never>?
    private var lastRemoteSyncAt: Date = .distantPast
    /// Push-off fallback poll (see Constants.Timing.conversationsPushOffPollInterval).
    /// Owned here so the View never owns polling. Started/stopped by the View's appear/disappear
    /// lifecycle via startPushOffPoll()/stopPushOffPoll(); stop() also tears it down.
    private var pushOffPollTimer: Timer?
    
    init(
        conversationService: any ConversationServiceProtocol = ConversationService.shared,
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.conversationService = conversationService
        self.profileService = profileService
        self.messageService = messageService
        self.authService = authService
    }

    /// Whether `start()` has registered the repository / NotificationCenter observers.
    private var hasStartedObservation = false

    /// Register the local-store and unread-count observers. Idempotent.
    ///
    /// Deliberately NOT called from `init`: SwiftUI re-evaluates `@State` initial values on
    /// every parent body pass, and subscribing to the repository's `CurrentValueSubject` here
    /// delivered the current value synchronously and wrote `conversations` while
    /// `MainTabView.body` was still being evaluated. Observation then invalidated the tab
    /// view, which constructed another throwaway ViewModel, and the cycle ran continuously
    /// (100 % CPU, taps delayed by seconds, eventual hang). Call this from the View's `.task`.
    func start() {
        guard !hasStartedObservation else { return }
        hasStartedObservation = true
        setupUnreadCountObservers()
        setupLocalObservation()
    }

    private func setupLocalObservation() {
        repository.getConversationsPublisher()
            .sink { [weak self] updatedConversations in
                guard let self else { return }
                self.applyLocalConversations(updatedConversations, animated: false)
                self.hydrateMissingProfilesIfNeeded()
            }
            .store(in: &cancellables)
    }

    /// Hydrate profiles as soon as the data that needs them arrives, rather than on the
    /// next poll tick. One tracked task at a time; a no-op when nothing is missing.
    private func hydrateMissingProfilesIfNeeded() {
        guard conversations.contains(where: { $0.otherParticipants.isEmpty }) else { return }
        guard hydrationTask == nil else { return }
        hydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.hydrateProfiles(for: self.conversations)
            self.hydrationTask = nil
        }
    }

    static func shouldShowLoading(conversations: [ConversationWithDetails]) -> Bool {
        conversations.isEmpty
    }

    func applyLocalConversations(_ updatedConversations: [ConversationWithDetails], animated: Bool = false) {
        // Filter out conversations the user has soft-deleted, then filter blocked
        let visible = filterBlockedConversations(filterHiddenConversations(updatedConversations))

        let mergedConversations = visible.map { updated in
            guard updated.otherParticipants.isEmpty,
                  let existing = conversations.first(where: { $0.id == updated.id }),
                  !existing.otherParticipants.isEmpty else {
                return updated
            }
            return ConversationWithDetails(
                conversation: updated.conversation,
                lastMessage: updated.lastMessage,
                unreadCount: updated.unreadCount,
                otherParticipants: existing.otherParticipants
            )
        }

        guard mergedConversations != conversations else { return }
        if animated {
            withAnimation(.easeInOut) {
                conversations = mergedConversations
            }
        } else {
            conversations = mergedConversations
        }
    }
    
    /// Exclude conversations the current user has soft-deleted (hidden via UserDefaults).
    private func filterHiddenConversations(_ conversations: [ConversationWithDetails]) -> [ConversationWithDetails] {
        guard let userId = authService.currentUserId else { return conversations }
        let hiddenIds = conversationService.getHiddenConversationIds(for: userId)
        guard !hiddenIds.isEmpty else { return conversations }
        return conversations.filter { !hiddenIds.contains($0.conversation.id) }
    }

    /// Hide conversations where every other participant is blocked.
    /// Group conversations with at least one non-blocked participant remain visible.
    /// Checks both otherParticipants (Profile) and conversation.participants (ConversationParticipant)
    /// because otherParticipants may not yet be hydrated when loading from SwiftData.
    private func filterBlockedConversations(_ conversations: [ConversationWithDetails]) -> [ConversationWithDetails] {
        guard let currentUserId = authService.currentUserId else { return conversations }
        return conversations.filter { convo in
            // Use otherParticipants (Profile objects) if available
            if !convo.otherParticipants.isEmpty {
                return convo.otherParticipants.contains { !MessageService.shared.isBlocked($0.id) }
            }
            // Fall back to conversation.participants (ConversationParticipant with userId)
            if let participants = convo.conversation.participants {
                let otherIds = participants.compactMap { $0.userId != currentUserId ? $0.userId : nil }
                guard !otherIds.isEmpty else { return true }
                return otherIds.contains { !MessageService.shared.isBlocked($0) }
            }
            // No participant data yet — keep for now, will be re-filtered after hydration
            return true
        }
    }
    
    /// Hide conversations that have no other member and no message: shells left behind when the
    /// participants insert failed (the pre-0005 RLS recursion) or a group everyone else has left.
    /// They rendered as "Unknown — No messages yet" rows that open to an empty thread.
    static func removingEmptyShells(
        _ conversations: [ConversationWithDetails],
        currentUserId: UUID
    ) -> [ConversationWithDetails] {
        conversations.filter { convo in
            guard convo.lastMessage == nil, convo.otherParticipants.isEmpty else { return true }
            // Participant ids may be known before profiles are hydrated; keep those rows.
            if let participants = convo.conversation.participants,
               participants.contains(where: { $0.userId != currentUserId }) {
                return true
            }
            return false
        }
    }

    /// One row per member set for threads that carry no messages (iMessage has exactly one
    /// thread per set of people). Duplicate untitled threads were created by "Message
    /// Participants" before the 20261005_0012 lookup existed; an empty one is hidden when a
    /// thread with the same members already has messages, and only the first of several empty
    /// ones is kept. Threads with messages and named groups are never hidden.
    static func removingEmptyDuplicates(
        _ conversations: [ConversationWithDetails],
        currentUserId: UUID
    ) -> [ConversationWithDetails] {
        func memberKey(_ convo: ConversationWithDetails) -> Set<UUID>? {
            guard (convo.conversation.title ?? "").isEmpty else { return nil }
            if let participants = convo.conversation.participants, !participants.isEmpty {
                return Set(participants.map(\.userId)).union([currentUserId])
            }
            if !convo.otherParticipants.isEmpty {
                return Set(convo.otherParticipants.map(\.id)).union([currentUserId])
            }
            return nil
        }

        var keysWithMessages = Set<Set<UUID>>()
        for convo in conversations where convo.lastMessage != nil {
            if let key = memberKey(convo) { keysWithMessages.insert(key) }
        }
        var seenEmptyKeys = Set<Set<UUID>>()
        return conversations.filter { convo in
            guard convo.lastMessage == nil, let key = memberKey(convo) else { return true }
            if keysWithMessages.contains(key) { return false }
            return seenEmptyKeys.insert(key).inserted
        }
    }

    /// The rows the list shows: blocked-user threads, empty shells and empty duplicates removed.
    private func visibleConversations() -> [ConversationWithDetails] {
        let unblocked = filterBlockedConversations(conversations)
        guard let currentUserId = authService.currentUserId else { return unblocked }
        return Self.removingEmptyDuplicates(
            Self.removingEmptyShells(unblocked, currentUserId: currentUserId),
            currentUserId: currentUserId
        )
    }

    private func recomputeFilteredConversations() {
        // Always apply the blocked / empty-shell / empty-duplicate filters on the output the view reads
        let blockedFiltered = visibleConversations()
        let newFiltered: [ConversationWithDetails]
        if searchText.isEmpty {
            newFiltered = blockedFiltered
        } else {
            let query = searchText.lowercased()
            newFiltered = blockedFiltered.filter { convo in
                // Search in conversation title
                if let title = convo.conversation.title?.lowercased(),
                   title.contains(query) {
                    return true
                }
                // Search in participant names
                let participantNames = convo.otherParticipants.map { $0.name.lowercased() }
                if participantNames.contains(where: { $0.contains(query) }) {
                    return true
                }
                // Search in last message
                if let lastMessage = convo.lastMessage?.text.lowercased(),
                   lastMessage.contains(query) {
                    return true
                }
                return false
            }
        }
        // Skip re-assignment if unchanged to avoid redundant objectWillChange emission
        guard newFiltered != filteredConversations else { return }
        filteredConversations = newFiltered
    }

    private func setupUnreadCountObservers() {
        NotificationCenter.default.publisher(for: .conversationUnreadCountsUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let details = notification.userInfo?["counts"] as? [BadgeCountManager.ConversationCountDetail] else {
                    return
                }
                self.applyUnreadCounts(details)
            }
            .store(in: &cancellables)
    }

    private func applyUnreadCounts(_ details: [BadgeCountManager.ConversationCountDetail]) {
        let countsById = Dictionary(uniqueKeysWithValues: details.map { ($0.conversationId, $0.unreadCount) })

        // Un-hide conversations that have unread messages but are currently hidden.
        // This covers messages that arrived while the app was closed.
        if let userId = authService.currentUserId {
            let loadedIds = Set(conversations.map { $0.conversation.id })
            let hiddenIds = conversationService.getHiddenConversationIds(for: userId)
            for detail in details where detail.unreadCount > 0 && !loadedIds.contains(detail.conversationId) {
                if hiddenIds.contains(detail.conversationId) {
                    conversationService.unhideConversationForUser(conversationId: detail.conversationId, userId: userId)
                    AppLogger.info("messaging", "[ConversationsListVM] Unhid conversation \(detail.conversationId) with \(detail.unreadCount) unread")
                    // Trigger a re-sync so the conversation reappears
                    Task { [weak self] in await self?.refreshConversations() }
                    return
                }
            }
        }

        var hasChanges = false
        var changedConversationIds = Set<UUID>()
        for index in conversations.indices {
            let conversationId = conversations[index].conversation.id
            let serverCount = countsById[conversationId] ?? 0

            if conversations[index].unreadCount != serverCount {
                let existing = conversations[index]
                conversations[index] = ConversationWithDetails(
                    conversation: existing.conversation,
                    lastMessage: existing.lastMessage,
                    unreadCount: serverCount,
                    otherParticipants: existing.otherParticipants
                )

                // Update local SwiftData unread count to keep it in sync
                if let sdConv = try? repository.fetchSDConversation(id: conversationId) {
                    sdConv.unreadCount = serverCount
                }

                hasChanges = true
                changedConversationIds.insert(conversationId)
            }
        }

        if hasChanges {
            AppLogger.info("messaging", "[ConversationsListVM] Applied server-side unread counts to list and local storage")
            try? repository.save(changedConversationIds: changedConversationIds)
        }
    }
    
    deinit {}

    /// Call from view onDisappear to cancel in-flight work so VM can tear down safely.
    func stop() {
        AppLogger.info("messaging", "[ConversationsListVM] stop() called; cancelling loadTask and searchTask")
        loadTask?.cancel()
        loadTask = nil
        searchTask?.cancel()
        searchTask = nil
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        hydrationTask?.cancel()
        hydrationTask = nil
        stopPushOffPoll()
    }

    // MARK: - Push-off fallback poll

    /// Start the conversations-list fallback poll used while push notifications are not
    /// authorized. Idempotent: a second call while a timer exists is a no-op.
    /// Each tick asks RefreshCoordinator for a staleness-gated refresh of `.conversations`
    /// (the coordinator still owns the decision, dedup, and backoff) and hydrates participant
    /// profiles for any conversation the refresh surfaced without them.
    func startPushOffPoll() {
        guard pushOffPollTimer == nil else { return }
        AppLogger.info("messaging", "[ConversationsListVM] Starting push-off conversations poll")
        pushOffPollTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.Timing.conversationsPushOffPollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pushOffPollTick()
            }
        }
    }

    /// Stop the push-off fallback poll. Safe to call when no poll is running.
    func stopPushOffPoll() {
        guard pushOffPollTimer != nil else { return }
        AppLogger.info("messaging", "[ConversationsListVM] Stopping push-off conversations poll")
        pushOffPollTimer?.invalidate()
        pushOffPollTimer = nil
    }

    private func pushOffPollTick() async {
        // The coordinator owns the decision, dedup and backoff. Conversations the refresh
        // surfaces arrive through the repository publisher, which hydrates missing
        // participant profiles itself (hydrateMissingProfilesIfNeeded).
        RefreshCoordinator.shared.refreshIfNeeded(.conversations, trigger: "pushOffPoll")
    }

    func loadConversations(trigger: String = "manualReload:conversations") async {
        // Skeleton rows only for the first load of a session. Someone with no conversations at
        // all would otherwise see the skeleton flash on every later reload.
        let showLoading = Self.shouldShowLoading(conversations: conversations) && lastRemoteSyncAt == .distantPast
        if showLoading {
            isLoading = true
        }
        // The defer used to sit inside the `if`, where it ran at once: the first load cleared
        // `isLoading` before anything was fetched, so the skeleton rows never showed and a
        // fresh sign-in saw "no conversations" until the first sync landed. When a remote sync
        // is started below, its task clears the flag instead.
        var remoteSyncOwnsLoadingFlag = false
        defer {
            if showLoading && !remoteSyncOwnsLoadingFlag { isLoading = false }
        }

        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        error = nil
        
        // 1. Load from local SwiftData immediately
        do {
            let localConversations = try repository.getConversations(for: userId)
            applyLocalConversations(localConversations, animated: false)
            // Set offset from local count so pagination works even before remote sync completes
            currentOffset = conversations.count
            AppLogger.info("messaging", "[ConversationsListVM] Loaded \(conversations.count) conversations from local storage")

            // Hydrate profiles for local conversations
            await hydrateProfiles(for: localConversations)
        } catch {
            AppLogger.warning("messaging", "[ConversationsListVM] Error loading local conversations: \(error)")
        }
        
        let now = Date()
        guard now.timeIntervalSince(lastRemoteSyncAt) >= Constants.Timing.messagingListRemoteSyncMinInterval else {
            return
        }
        lastRemoteSyncAt = now

        // 2. Remote sync is owned by RefreshCoordinator → MessagingSyncEngine.refreshConversationList()
        //    → BackgroundSyncActor; the repository publisher re-emits after that save. The task is stored
        //    so stop() can cancel *our* wait — the coordinator's task itself is never cancelled here.
        loadTask?.cancel()
        remoteSyncOwnsLoadingFlag = showLoading
        loadTask = Task { @MainActor in
            defer {
                loadTask = nil
                if showLoading { isLoading = false }
            }
            let result = await RefreshCoordinator.shared.forceFullRefreshAndWait(.conversations, trigger: trigger)
            guard !Task.isCancelled else { return }
            if case .failed(let error, _)? = result {
                AppLogger.error("messaging", "[ConversationsListVM] Error syncing conversations: \(error)")
                return
            }
            do {
                let updatedConversations = try repository.getConversations(for: userId)
                self.applyLocalConversations(updatedConversations, animated: false)
                currentOffset = self.conversations.count
                hasMoreConversations = true // Reset so pagination can continue after sync
                await hydrateProfiles(for: updatedConversations)
            } catch {
                if !Task.isCancelled {
                    AppLogger.error("messaging", "[ConversationsListVM] Error reading synced conversations: \(error)")
                }
            }
        }
    }

    private func hydrateProfiles(for conversations: [ConversationWithDetails]) async {
        guard let currentUserId = authService.currentUserId else { return }
        guard !conversations.isEmpty else { return }

        let allOtherParticipantIds = Set(
            conversations.flatMap { conversation in
                (conversation.conversation.participants ?? [])
                    .map(\.userId)
                    .filter { $0 != currentUserId }
            }
        )
        guard !allOtherParticipantIds.isEmpty else { return }

        var profiles: [Profile]
        do {
            profiles = try await profileService.fetchProfiles(userIds: Array(allOtherParticipantIds))
        } catch {
            AppLogger.warning("messaging", "[ConversationsListVM] Batch profile hydration failed, falling back to cache: \(error.localizedDescription)")
            // Fall back to cache-only lookup so previously-fetched profiles still appear
            var cached: [Profile] = []
            for id in allOtherParticipantIds {
                if let p = await CacheManager.shared.getCachedProfile(id: id) {
                    cached.append(p)
                }
            }
            guard !cached.isEmpty else { return }
            profiles = cached
        }
        let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        var updatedConversations = conversations
        var hasChanges = false
        
        for i in 0..<updatedConversations.count {
            let convWithDetails = updatedConversations[i]
            let participantIds = convWithDetails.conversation.participants?.map { $0.userId } ?? []
            let otherParticipantIds = participantIds.filter { $0 != currentUserId }

            let otherProfiles = otherParticipantIds.compactMap { profilesById[$0] }
            if !otherProfiles.isEmpty {
                updatedConversations[i] = ConversationWithDetails(
                    conversation: convWithDetails.conversation,
                    lastMessage: convWithDetails.lastMessage,
                    unreadCount: convWithDetails.unreadCount,
                    otherParticipants: otherProfiles
                )
                hasChanges = true
            }
        }
        
        if hasChanges {
            applyLocalConversations(updatedConversations, animated: false)
        }
    }
    
    func loadMoreConversations() async {
        guard !isLoadingMore, hasMoreConversations,
              let userId = authService.currentUserId else {
            return
        }
        
        isLoadingMore = true
        
        do {
            AppLogger.info("messaging", "[ConversationsListVM] Fetching more conversations at offset \(currentOffset)")
            let fetched = try await conversationService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            
            // Filter out duplicates to prevent UI glitches
            let existingIds = Set(self.conversations.map { $0.conversation.id })
            let newConversations = fetched.filter { !existingIds.contains($0.conversation.id) }

            if !newConversations.isEmpty {
                self.conversations.append(contentsOf: newConversations)
                AppLogger.info("messaging", "[ConversationsListVM] Loaded \(newConversations.count) more conversations")
            }

            // Always advance the offset to avoid re-fetching the same page
            currentOffset += fetched.count

            // End of list: server returned fewer than requested, OR a full
            // page of duplicates (no forward progress — prevents stuck spinner)
            if fetched.count < pageSize || newConversations.isEmpty {
                hasMoreConversations = false
                AppLogger.info("messaging", "[ConversationsListVM] Reached the end of the conversation list (fetched=\(fetched.count), new=\(newConversations.count), pageSize=\(pageSize))")
            }
        } catch {
            // Don't show error if task was cancelled
            if Task.isCancelled || error is CancellationError || error.localizedDescription.lowercased().contains("cancel") {
                AppLogger.info("messaging", "Load more conversations task was cancelled, ignoring error")
            } else {
                AppLogger.error("messaging", "Error loading more conversations: \(error.localizedDescription)")
                // Don't set error here - just log it
            }
        }
        
        isLoadingMore = false
    }
    
    func refreshConversations() async {
        guard let _ = authService.currentUserId else { return }
        // Reset pagination state so loadMore works correctly after refresh
        currentOffset = 0
        hasMoreConversations = true
        lastRemoteSyncAt = .distantPast
        await loadConversations(trigger: "pullToRefresh:conversations")
        // Pull-to-refresh: keep the spinner up until the coordinator-owned sync has finished.
        await loadTask?.value
    }

    func deleteConversation(_ conversation: Conversation) async {
        // Optimistically remove from the list for responsive UI
        let snapshot = conversations
        
        withAnimation {
            conversations.removeAll { $0.conversation.id == conversation.id }
        }
        
        do {
            try await repository.deleteConversation(id: conversation.id)
            AppLogger.info("messaging", "[ConversationsListVM] Soft-deleted conversation \(conversation.id)")
        } catch {
            // Restore the list on failure so the user can retry
            withAnimation {
                conversations = snapshot
            }
            self.error = AppError.processingError("Failed to delete conversation: \(error.localizedDescription)")
            AppLogger.error("messaging", "[ConversationsListVM] Failed to delete conversation: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Mute

    func loadMutedConversations() async {
        guard let userId = authService.currentUserId else { return }
        mutedConversations = await muteService.fetchMutedConversationIds(userId: userId)
    }

    func muteConversation(id conversationId: UUID, duration: ConversationMuteService.MuteDuration) async {
        guard let userId = authService.currentUserId else { return }
        try? await muteService.muteConversation(
            conversationId: conversationId,
            userId: userId,
            duration: duration
        )
        withAnimation {
            _ = mutedConversations.insert(conversationId)
        }
    }

    func unmuteConversation(id conversationId: UUID) async {
        guard let userId = authService.currentUserId else { return }
        try? await muteService.unmuteConversation(
            conversationId: conversationId,
            userId: userId
        )
        withAnimation {
            _ = mutedConversations.remove(conversationId)
        }
    }

    // MARK: - Compose

    /// Create or find the conversation for the selected users.
    /// - If 1 user selected: creates/finds the direct message (2 participants)
    /// - If 2+ users selected: finds an existing group with exactly these participants, else creates one
    /// - Returns: The conversation ID to navigate to, or nil on failure (logged)
    func createOrFindConversation(with userIds: [UUID]) async -> UUID? {
        guard let currentUserId = authService.currentUserId else { return nil }
        guard !userIds.isEmpty else { return nil }
        
        AppLogger.info("messaging", "[ConversationsListVM] Looking for existing conversation with \(userIds.count) user(s)")
        
        do {
            let conversation: Conversation
            
            if userIds.count == 1 {
                // Direct message: getOrCreateDirectConversation already checks for existing
                AppLogger.info("messaging", "[ConversationsListVM] Creating/finding direct message")
                conversation = try await conversationService.getOrCreateDirectConversation(
                    userId: currentUserId,
                    otherUserId: userIds[0]
                )
            } else {
                // Group conversation: Check if one exists with exactly these participants
                let allParticipantIds = Set([currentUserId] + userIds)
                
                AppLogger.info("messaging", "[ConversationsListVM] Looking for group with participants: \(allParticipantIds.count) total")
                
                if let existingConversation = try await findExistingGroupConversation(participantIds: allParticipantIds, userId: currentUserId) {
                    AppLogger.info("messaging", "[ConversationsListVM] Found existing group conversation: \(existingConversation.id)")
                    conversation = existingConversation
                } else {
                    // Create new group conversation
                    AppLogger.info("messaging", "[ConversationsListVM] Creating new group conversation")
                    conversation = try await conversationService.createConversationWithUsers(
                        userIds: Array(allParticipantIds),
                        createdBy: currentUserId,
                        title: nil // User can set group name later
                    )
                }
            }
            
            // Composing to these people again brings back a thread the user had hidden with
            // Delete; otherwise it stays out of the list until someone else writes in it.
            conversationService.unhideConversationForUser(conversationId: conversation.id, userId: currentUserId)

            AppLogger.info("messaging", "[ConversationsListVM] Navigating to conversation: \(conversation.id)")
            return conversation.id
        } catch {
            AppLogger.error("messaging", "[ConversationsListVM] Error creating/navigating to conversation: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Find an existing group conversation with an exact participant match.
    /// One batched participant query replaces the former one-query-per-conversation loop (up to 100 queries).
    /// A failed conversations fetch throws (aborting the flow, as before); a failed participant lookup
    /// yields "no match" (the old per-conversation `try?` semantics), so creation proceeds.
    private func findExistingGroupConversation(participantIds: Set<UUID>, userId: UUID) async throws -> Conversation? {
        // Get all user's conversations
        let conversations = try await conversationService.fetchConversations(
            userId: userId,
            limit: Constants.PageSizes.fetchAll,
            offset: 0
        )
        guard !conversations.isEmpty else { return nil }
        
        // Active participant rows (left_at IS NULL) in one query: a group matches on its current member set
        let participantsByConversation = (try? await participantService.fetchParticipantIdsByConversation(
            conversationIds: conversations.map { $0.conversation.id }
        )) ?? [:]
        
        // Check each conversation for exact participant match
        for convDetail in conversations {
            if participantsByConversation[convDetail.conversation.id] == participantIds {
                return convDetail.conversation
            }
        }
        
        return nil
    }
    
    // MARK: - Search
    
    private var searchDebounceTask: Task<Void, Never>?

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isSearching = true
            
            guard let userId = self.authService.currentUserId else {
                self.isSearching = false
                return
            }
            
            do {
                let messages = try await self.messageService.searchMessages(query: query, userId: userId, limit: Constants.PageSizes.searchMessages)
                
                guard !Task.isCancelled else { return }
                
                // Map messages to search results with conversation titles
                let results = messages.map { message -> MessageSearchResult in
                    let title = self.conversationTitle(for: message.conversationId)
                    return MessageSearchResult(
                        message: message,
                        conversationId: message.conversationId,
                        conversationTitle: title
                    )
                }
                
                self.searchResults = results
            } catch {
                if !Task.isCancelled {
                    AppLogger.error("messaging", "[ConversationsListVM] Search failed: \(error.localizedDescription)")
                }
            }
            
            if !Task.isCancelled {
                self.isSearching = false
            }
        }
    }
    
    /// Resolve a conversation title from the loaded conversations list
    private func conversationTitle(for conversationId: UUID) -> String {
        if let detail = conversations.first(where: { $0.conversation.id == conversationId }) {
            // Use group title if available
            if let title = detail.conversation.title, !title.isEmpty {
                return title
            }
            // Otherwise use participant names
            if !detail.otherParticipants.isEmpty {
                return detail.otherParticipants.map { $0.name }.joined(separator: ", ")
            }
        }
        return "messaging_chat_fallback".localized
    }
    
    // MARK: - Debug Support
    
    /// Get debug information about the current state
    func getDebugInfo() -> String {
        var info = """
        === Conversations List Debug Info ===
        Loaded Conversations: \(conversations.count)
        Is Loading: \(isLoading)
        Is Loading More: \(isLoadingMore)
        Has More: \(hasMoreConversations)
        Current Offset: \(currentOffset)
        Page Size: \(pageSize)
        """
        
        if let error = error {
            info += "\nError: \(error.localizedDescription)"
        }
        
        if !conversations.isEmpty {
            info += "\n\nFirst 5 Conversations:"
            for (index, conv) in conversations.prefix(5).enumerated() {
                info += "\n  \(index + 1). ID: \(conv.conversation.id)"
                info += "\n     Participants: \(conv.otherParticipants.count)"
                info += "\n     Last Message: \(conv.lastMessage?.text.prefix(30) ?? "None")"
            }
        }
        
        return info
    }
}
