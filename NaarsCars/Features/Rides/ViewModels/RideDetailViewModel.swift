//
//  RideDetailViewModel.swift
//  NaarsCars
//
//  ViewModel for ride detail view
//

import Foundation
internal import Combine

/// ViewModel for ride detail view
@MainActor
final class RideDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var ride: Ride?
    @Published var qaItems: [RequestQA] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var showCalendarOffer: Bool = false
    /// The ride was deleted, or moderators hid it from everyone but its poster. Retrying
    /// cannot bring it back, so the screen shows a "no longer available" state instead of
    /// an error with a Retry button.
    @Published var isUnavailable: Bool = false
    /// True while "Message Participants" is finding or creating the group thread.
    @Published var isOpeningConversation: Bool = false

    // MARK: - Private Properties

    private let rideService: any RideServiceProtocol
    private let authService: any AuthServiceProtocol
    /// Messaging seam used only to open a group chat for this ride (narrow protocol, not the concrete service)
    private let conversationService: any ConversationServiceProtocol
    /// Block list only: questions from someone the viewer has blocked are not shown, as in
    /// Town Hall (narrow protocol, not the concrete service)
    private let messageService: any MessageServiceProtocol
    private let notificationRepository = NotificationRepository.shared

    init(
        rideService: any RideServiceProtocol = RideService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        conversationService: any ConversationServiceProtocol = ConversationService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared
    ) {
        self.rideService = rideService
        self.authService = authService
        self.conversationService = conversationService
        self.messageService = messageService
    }
    
    // MARK: - Public Methods
    
    /// Check if there are unread notifications of specific types for this ride
    func hasUnreadNotifications(of types: [NotificationType]) async -> Bool {
        guard let ride = ride else { return false }
        return notificationRepository.hasUnreadNotifications(requestId: ride.id, types: types)
    }
    
    /// Load ride details
    /// - Parameter id: Ride ID
    func loadRide(id: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Load ride and Q&A concurrently
            async let rideTask = rideService.fetchRide(id: id)
            async let qaTask = rideService.fetchQA(requestId: id, requestType: "ride")
            
            let (fetchedRide, fetchedQA) = try await (rideTask, qaTask)
            
            ride = fetchedRide
            qaItems = fetchedQA.filter { !messageService.isBlocked($0.userId) }
            isUnavailable = false
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            if let appError = error as? AppError, case .notFound = appError {
                ride = nil
                qaItems = []
                isUnavailable = true
                return
            }
            self.error = error.localizedDescription
            AppLogger.error("rides", "Error loading ride: \(error)")
        }
    }
    
    /// Post a question on this ride
    /// - Parameter question: Question text
    func postQuestion(_ question: String) async {
        guard AuthService.shared.currentUserId != nil else { return }
        guard canAskQuestions else {
            error = "ride_edit_questions_disabled".localized
            return
        }
        guard let rideId = ride?.id,
              let userId = authService.currentUserId else {
            error = "common_not_authenticated".localized
            return
        }
        
        do {
            let qa = try await rideService.postQuestion(
                requestId: rideId,
                requestType: "ride",
                userId: userId,
                question: question
            )
            
            qaItems.append(qa)
            HapticManager.lightImpact()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Delete this ride
    func deleteRide() async throws {
        guard let rideId = ride?.id else {
            throw AppError.invalidInput("No ride to delete")
        }
        
        try await rideService.deleteRide(id: rideId)
        RequestsDashboardRefresh.afterUserAction("deleteRide")
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
            AppLogger.error("rides", "Error deleting question: \(error.localizedDescription)")
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
        guard let ride = ride, let currentUserId = authService.currentUserId else { return nil }
        isOpeningConversation = true
        defer { isOpeningConversation = false }

        do {
            var participantIds: Set<UUID> = [ride.userId]
            if let claimedBy = ride.claimedBy { participantIds.insert(claimedBy) }
            if let participants = ride.participants {
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
            AppLogger.error("rides", "Error creating conversation: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Add participants to this ride and reload it.
    /// - Returns: false when the participants could not be added (also logged), so the screen
    ///   can say so; this used to fail silently.
    @discardableResult
    func addParticipants(_ userIds: [UUID]) async -> Bool {
        guard let currentUserId = authService.currentUserId,
              let ride = ride else { return false }

        do {
            try await rideService.addRideParticipants(
                rideId: ride.id,
                userIds: userIds,
                addedBy: currentUserId
            )
            RequestsDashboardRefresh.afterUserAction("addRideParticipants")
            await loadRide(id: ride.id)
            return true
        } catch {
            AppLogger.error("rides", "Error adding participants to ride: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check if current user is the poster
    var isPoster: Bool {
        guard let ride = ride,
              let currentUserId = authService.currentUserId else {
            return false
        }
        return ride.userId == currentUserId
    }
    
    /// Check if current user is a participant
    var isParticipant: Bool {
        guard let ride = ride,
              let currentUserId = authService.currentUserId else {
            return false
        }
        return ride.participants?.contains(where: { $0.id == currentUserId }) ?? false
    }
    
    /// Whether the current user may change this ride (add participants, and with the two
    /// checks below, edit or delete). Poster only: RLS rejects a participant's delete and
    /// participant insert, and a participant's Delete used to show the success checkmark for
    /// a ride that was still there.
    var canEdit: Bool {
        return isPoster
    }

    /// Edit is offered until the ride is completed.
    var canEditDetails: Bool {
        guard let ride = ride else { return false }
        return canEdit && ride.status != .completed
    }

    /// Delete is offered until the ride has been fulfilled. A completed ride somebody helped
    /// with (and may have been reviewed for) stays; an expired, never-claimed one can go.
    var canDelete: Bool {
        guard let ride = ride else { return false }
        return canEdit && !(ride.status == .completed && ride.claimedBy != nil)
    }

    /// Whether Q&A submissions are allowed for this ride
    var canAskQuestions: Bool {
        guard let ride = ride else { return false }
        return ride.claimedBy == nil
    }

    // MARK: - Calendar Offer

    /// Check and trigger calendar offer for confirmed rides
    func checkCalendarOffer() {
        guard let ride = ride,
              ride.status == .confirmed,
              let currentUserId = authService.currentUserId else { return }

        // Offer only to the claimer — the person who committed to be there. Posters and
        // participants were re-prompted on every open (and on every push-tap) until the
        // dismissal cap was reached.
        guard ride.claimedBy == currentUserId else { return }

        // Check tracker
        guard CalendarOfferTracker.shared.shouldOffer(requestType: "ride", requestId: ride.id) else { return }

        // Don't offer for past events
        let eventTime = RequestItem.ride(ride).eventTime
        guard eventTime > Date() else { return }

        // Brief delay so the view settles before showing alert
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.calendarOfferPresentationDelay) { [weak self] in
            self?.showCalendarOffer = true
        }
    }

    /// Handle user accepting the calendar offer
    func acceptCalendarOffer() async {
        guard let ride = ride else { return }
        let eventId = await CalendarService.shared.createEventForRide(ride)
        if eventId != nil {
            CalendarOfferTracker.shared.recordEventCreated(requestType: "ride", requestId: ride.id)
        }
    }

    /// Handle user dismissing the calendar offer
    func dismissCalendarOffer() {
        guard let ride = ride else { return }
        CalendarOfferTracker.shared.recordDismissal(requestType: "ride", requestId: ride.id)
    }
}





