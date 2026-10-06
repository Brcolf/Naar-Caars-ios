//
//  FavorDetailViewModel.swift
//  NaarsCars
//
//  ViewModel for favor detail view
//

import Foundation
internal import Combine

/// ViewModel for favor detail view
@MainActor
final class FavorDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var favor: Favor?
    @Published var qaItems: [RequestQA] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showCalendarOffer: Bool = false
    /// The favor was deleted, or moderators hid it from everyone but its poster. Retrying
    /// cannot bring it back, so the screen shows a "no longer available" state instead of
    /// an error with a Retry button.
    @Published var isUnavailable: Bool = false
    /// True while "Message Participants" is finding or creating the group thread.
    @Published var isOpeningConversation: Bool = false

    // MARK: - Private Properties

    private let favorService: any FavorServiceProtocol
    private let rideService: any RideServiceProtocol // Reuse RideService for Q&A
    private let authService: any AuthServiceProtocol
    /// Messaging seam used only to open a group chat for this favor (narrow protocol, not the concrete service)
    private let conversationService: any ConversationServiceProtocol
    /// Block list only: questions from someone the viewer has blocked are not shown, as in
    /// Town Hall (narrow protocol, not the concrete service)
    private let messageService: any MessageServiceProtocol
    private let notificationRepository = NotificationRepository.shared

    init(
        favorService: any FavorServiceProtocol = FavorService.shared,
        rideService: any RideServiceProtocol = RideService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        conversationService: any ConversationServiceProtocol = ConversationService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared
    ) {
        self.favorService = favorService
        self.rideService = rideService
        self.authService = authService
        self.conversationService = conversationService
        self.messageService = messageService
    }
    
    // MARK: - Public Methods
    
    /// Check if there are unread notifications of specific types for this favor
    func hasUnreadNotifications(of types: [NotificationType]) async -> Bool {
        guard let favor = favor else { return false }
        return notificationRepository.hasUnreadNotifications(requestId: favor.id, types: types)
    }
    
    /// Load favor details
    /// - Parameter id: Favor ID
    func loadFavor(id: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Load favor and Q&A concurrently
            async let favorTask = favorService.fetchFavor(id: id)
            async let qaTask = rideService.fetchQA(requestId: id, requestType: "favor")
            
            let (fetchedFavor, fetchedQA) = try await (favorTask, qaTask)
            
            favor = fetchedFavor
            qaItems = fetchedQA.filter { !messageService.isBlocked($0.userId) }
            isUnavailable = false
        } catch {
            if let appError = error as? AppError, case .notFound = appError {
                favor = nil
                qaItems = []
                isUnavailable = true
                return
            }
            self.error = error.localizedDescription
            AppLogger.error("favors", "Error loading favor: \(error.localizedDescription)")
        }
    }
    
    /// Post a question on this favor
    /// - Parameter question: Question text
    func postQuestion(_ question: String) async {
        guard AuthService.shared.currentUserId != nil else { return }
        guard canAskQuestions else {
            error = "favor_edit_questions_disabled".localized
            return
        }
        guard let favorId = favor?.id,
              let userId = authService.currentUserId else {
            error = "common_not_authenticated".localized
            return
        }
        
        do {
            let qa = try await rideService.postQuestion(
                requestId: favorId,
                requestType: "favor",
                userId: userId,
                question: question
            )
            
            qaItems.append(qa)
            HapticManager.lightImpact()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Delete this favor
    func deleteFavor() async throws {
        guard let favorId = favor?.id else {
            throw AppError.invalidInput("No favor to delete")
        }
        
        try await favorService.deleteFavor(id: favorId)
        RequestsDashboardRefresh.afterUserAction("deleteFavor")
    }

    /// Delete a question the signed-in user asked (RLS allows nobody else to).
    /// - Returns: true once the row is gone; false on failure (logged)
    func deleteQuestion(_ qa: RequestQA) async -> Bool {
        guard qa.userId == authService.currentUserId else { return false }
        do {
            try await rideService.deleteQuestion(id: qa.id)
            qaItems.removeAll { $0.id == qa.id }
            return true
        } catch {
            AppLogger.error("favors", "Error deleting question: \(error.localizedDescription)")
            return false
        }
    }

    /// Drop the questions of anyone the viewer has blocked since the list was loaded. Block is
    /// on the asker's profile, reached from their avatar in the Q&A list, so this runs when the
    /// list comes back on screen.
    func removeBlockedQuestions() {
        guard qaItems.contains(where: { messageService.isBlocked($0.userId) }) else { return }
        qaItems.removeAll { messageService.isBlocked($0.userId) }
    }

    /// Create a group conversation with the poster, claimer, participants and the current user.
    /// - Returns: The conversation ID to navigate to, or nil on failure (logged)
    func createConversationWithParticipants() async -> UUID? {
        // Lookup then create is not atomic; a second tap inside one round trip could miss the
        // lookup too and create a duplicate thread. The view checks this flag before calling.
        guard !isOpeningConversation else { return nil }
        guard let favor = favor, let currentUserId = authService.currentUserId else { return nil }
        isOpeningConversation = true
        defer { isOpeningConversation = false }

        do {
            var participantIds: Set<UUID> = [favor.userId]
            if let claimedBy = favor.claimedBy { participantIds.insert(claimedBy) }
            if let participants = favor.participants {
                participantIds.formUnion(participants.map { $0.id })
            }
            participantIds.insert(currentUserId)

            // iMessage semantics: reuse the thread for this exact member set instead of creating
            // another one on every tap (six duplicate threads existed on 2026-10-05).
            if let existing = await conversationService.findConversation(forParticipants: Array(participantIds)) {
                return existing
            }
            
            let conversation = try await conversationService.createConversationWithUsers(
                userIds: Array(participantIds),
                createdBy: currentUserId,
                title: nil
            )
            
            return conversation.id
        } catch {
            AppLogger.error("favors", "Error creating conversation: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Add participants to this favor and reload it.
    /// - Returns: false when the participants could not be added (also logged), so the screen
    ///   can say so; this used to fail silently.
    @discardableResult
    func addParticipants(_ userIds: [UUID]) async -> Bool {
        guard let currentUserId = authService.currentUserId,
              let favor = favor else { return false }

        do {
            try await favorService.addFavorParticipants(
                favorId: favor.id,
                userIds: userIds,
                addedBy: currentUserId
            )
            RequestsDashboardRefresh.afterUserAction("addFavorParticipants")
            await loadFavor(id: favor.id)
            return true
        } catch {
            AppLogger.error("favors", "Error adding participants to favor: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check if current user is the poster
    var isPoster: Bool {
        guard let favor = favor,
              let currentUserId = authService.currentUserId else {
            return false
        }
        return favor.userId == currentUserId
    }
    
    /// Check if current user is a participant
    var isParticipant: Bool {
        guard let favor = favor,
              let currentUserId = authService.currentUserId else {
            return false
        }
        return favor.participants?.contains(where: { $0.id == currentUserId }) ?? false
    }
    
    /// Whether the current user may change this favor (add participants, and with the two
    /// checks below, edit or delete). Poster only: RLS rejects a participant's delete and
    /// participant insert, and a participant's Delete used to show the success checkmark for
    /// a favor that was still there.
    var canEdit: Bool {
        return isPoster
    }

    /// Edit is offered until the favor is completed.
    var canEditDetails: Bool {
        guard let favor = favor else { return false }
        return canEdit && favor.status != .completed
    }

    /// Delete is offered until the favor has been fulfilled. A completed favor somebody helped
    /// with (and may have been reviewed for) stays; an expired, never-claimed one can go.
    var canDelete: Bool {
        guard let favor = favor else { return false }
        return canEdit && !(favor.status == .completed && favor.claimedBy != nil)
    }

    /// Whether Q&A submissions are allowed for this favor
    var canAskQuestions: Bool {
        guard let favor = favor else { return false }
        return favor.claimedBy == nil
    }

    // MARK: - Calendar Offer

    /// Check and trigger calendar offer for confirmed favors
    func checkCalendarOffer() {
        guard let favor = favor,
              favor.status == .confirmed,
              let currentUserId = authService.currentUserId else { return }

        let isClaimer = favor.claimedBy == currentUserId
        let isParticipant = favor.participants?.contains(where: { $0.id == currentUserId }) ?? false
        let isPoster = favor.userId == currentUserId
        guard isClaimer || isParticipant || isPoster else { return }

        guard CalendarOfferTracker.shared.shouldOffer(requestType: "favor", requestId: favor.id) else { return }

        // `windowEnd`, not `eventTime`: a favor with no time starts at midnight, so one dated
        // today was already "past" and its all-day calendar event was never offered.
        guard RequestItem.favor(favor).windowEnd > Date() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.calendarOfferPresentationDelay) { [weak self] in
            self?.showCalendarOffer = true
        }
    }

    /// Handle user accepting the calendar offer
    func acceptCalendarOffer() async {
        guard let favor = favor else { return }
        let eventId = await CalendarService.shared.createEventForFavor(favor)
        if eventId != nil {
            CalendarOfferTracker.shared.recordEventCreated(requestType: "favor", requestId: favor.id)
        }
    }

    /// Handle user dismissing the calendar offer
    func dismissCalendarOffer() {
        guard let favor = favor else { return }
        CalendarOfferTracker.shared.recordDismissal(requestType: "favor", requestId: favor.id)
    }
}





