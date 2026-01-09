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
    
    // MARK: - Public Methods
    
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
            print("❌ Error loading ride: \(error)")
        }
    }
    
    /// Post a question on this ride
    /// - Parameter question: Question text
    func postQuestion(_ question: String) async {
        guard let rideId = ride?.id,
              let userId = authService.currentUserId else {
            error = "Not authenticated"
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
}




