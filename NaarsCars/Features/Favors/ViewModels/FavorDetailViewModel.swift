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
    
    // MARK: - Private Properties
    
    private let favorService = FavorService.shared
    private let rideService = RideService.shared // Reuse RideService for Q&A
    private let authService = AuthService.shared
    
    // MARK: - Public Methods
    
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
            print("❌ Error loading favor: \(error)")
        }
    }
    
    /// Post a question on this favor
    /// - Parameter question: Question text
    func postQuestion(_ question: String) async {
        guard let favorId = favor?.id,
              let userId = authService.currentUserId else {
            error = "Not authenticated"
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
}





