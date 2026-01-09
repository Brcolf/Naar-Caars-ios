//
//  CreateRideViewModel.swift
//  NaarsCars
//
//  ViewModel for creating a new ride request
//

import Foundation
internal import Combine

/// ViewModel for creating a new ride request
@MainActor
final class CreateRideViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var date: Date = Date()
    @Published var time: String = ""
    @Published var pickup: String = ""
    @Published var destination: String = ""
    @Published var seats: Int = 1
    @Published var notes: String = ""
    @Published var gift: String = ""
    
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let rideService = RideService.shared
    private let authService = AuthService.shared
    
    // MARK: - Public Methods
    
    /// Validate form fields
    /// - Returns: Error message if validation fails, nil if valid
    func validateForm() -> String? {
        if pickup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Pickup location is required"
        }
        
        if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Destination is required"
        }
        
        if time.isEmpty {
            return "Time is required"
        }
        
        // Validate time format (HH:mm:ss or HH:mm)
        let timePattern = #"^([0-1]?[0-9]|2[0-3]):[0-5][0-9](:([0-5][0-9]))?$"#
        if (time.range(of: timePattern, options: .regularExpression) == nil) != nil {
            return "Time must be in format HH:mm or HH:mm:ss"
        }
        
        // Validate date is not in the past
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selectedDate = calendar.startOfDay(for: date)
        
        if selectedDate < today {
            return "Date cannot be in the past"
        }
        
        if seats < 1 || seats > 7 {
            return "Seats must be between 1 and 7"
        }
        
        return nil
    }
    
    /// Create the ride request
    /// - Returns: Created ride if successful
    /// - Throws: AppError if creation fails
    func createRide() async throws -> Ride {
        // Validate form
        if let error = validateForm() {
            throw AppError.invalidInput(error)
        }
        
        // Get current user ID
        guard let userId = authService.currentUserId else {
            throw AppError.authenticationRequired
        }
        
        // Format time to HH:mm:ss if needed
        let formattedTime = formatTime(time)
        
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let ride = try await rideService.createRide(
                userId: userId,
                date: date,
                time: formattedTime,
                pickup: pickup.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                seats: seats,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines),
                gift: gift.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gift.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            return ride
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    /// Format time string to HH:mm:ss format
    private func formatTime(_ time: String) -> String {
        // If already in HH:mm:ss format, return as is
        if time.components(separatedBy: ":").count == 3 {
            return time
        }
        
        // If in HH:mm format, add :00
        if time.components(separatedBy: ":").count == 2 {
            return time + ":00"
        }
        
        // Default fallback
        return time
    }
}




