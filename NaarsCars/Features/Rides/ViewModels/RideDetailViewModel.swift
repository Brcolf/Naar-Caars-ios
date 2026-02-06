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
    
    // MARK: - Private Properties
    
    private let rideService = RideService.shared
    private let authService = AuthService.shared
    private let notificationRepository = NotificationRepository.shared
    
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
            qaItems = fetchedQA
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("rides", "Error loading ride: \(error)")
        }
    }
    
    /// Post a question on this ride
    /// - Parameter question: Question text
    func postQuestion(_ question: String) async {
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
    
    /// Check if current user can edit/delete (poster or participant)
    var canEdit: Bool {
        return isPoster || isParticipant
    }

    /// Whether Q&A submissions are allowed for this ride
    var canAskQuestions: Bool {
        guard let ride = ride else { return false }
        return ride.claimedBy == nil
    }
}





