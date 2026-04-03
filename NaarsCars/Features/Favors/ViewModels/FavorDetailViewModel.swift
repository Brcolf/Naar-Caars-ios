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
    
    // MARK: - Private Properties
    
    private let favorService: any FavorServiceProtocol
    private let rideService: any RideServiceProtocol // Reuse RideService for Q&A
    private let authService: any AuthServiceProtocol
    private let notificationRepository = NotificationRepository.shared

    init(
        favorService: any FavorServiceProtocol = FavorService.shared,
        rideService: any RideServiceProtocol = RideService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.favorService = favorService
        self.rideService = rideService
        self.authService = authService
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
            qaItems = fetchedQA
        } catch {
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
    
    /// Check if current user can edit/delete (poster or participant)
    var canEdit: Bool {
        return isPoster || isParticipant
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

        let eventTime = RequestItem.favor(favor).eventTime
        guard eventTime > Date() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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





