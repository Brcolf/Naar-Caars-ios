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
    @Published var hour: Int = 9
    @Published var minute: Int = 0
    @Published var isAM: Bool = true
    @Published var pickup: String = ""
    @Published var destination: String = ""
    @Published var seats: Int = 1
    @Published var notes: String = ""
    @Published var gift: String = ""
    @Published var selectedParticipantIds: Set<UUID> = []
    
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let rideService: any RideServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        rideService: any RideServiceProtocol = RideService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.rideService = rideService
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    /// Validate form fields
    /// - Returns: Error message if validation fails, nil if valid
    func validateForm() -> String? {
        if pickup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "ride_error_pickup_required".localized
        }
        
        if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "ride_error_destination_required".localized
        }
        
        // Validate date is not in the past
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selectedDate = calendar.startOfDay(for: date)
        
        if selectedDate < today {
            return "ride_error_date_in_past".localized
        }
        
        if seats < 1 || seats > 7 {
            return "ride_error_seats_range".localized
        }
        
        return nil
    }
    
    /// Create the ride request
    /// - Returns: Created ride if successful
    /// - Throws: AppError if creation fails
    func createRide() async throws -> Ride {
        // Validate form
        if let validationError = validateForm() {
            self.error = validationError
            throw AppError.invalidInput(validationError)
        }
        
        // Get current user ID
        guard let userId = authService.currentUserId else {
            self.error = "Authentication required. Please sign in again."
            throw AppError.authenticationRequired
        }
        
        // Format time from hour/minute/isAM to HH:mm:ss
        let formattedTime = formatTime(hour: hour, minute: minute, isAM: isAM)
        
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
            
            // Add participants if any were selected (max 5)
            let participantIds = Array(selectedParticipantIds.prefix(5))
            if !participantIds.isEmpty {
                try? await rideService.addRideParticipants(
                    rideId: ride.id,
                    userIds: participantIds,
                    addedBy: userId
                )
            }
            
            return ride
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    /// Format time from hour/minute/isAM to HH:mm:ss format (24-hour)
    /// - Parameters:
    ///   - hour: Hour (1-12)
    ///   - minute: Minute (0-59)
    ///   - isAM: true for AM, false for PM
    /// - Returns: Time string in HH:mm:ss format
    func formatTime(hour: Int, minute: Int, isAM: Bool) -> String {
        var hour24 = hour
        
        // Convert 12-hour to 24-hour format
        if isAM {
            // AM: 12 AM = 0, 1-11 AM = 1-11
            if hour == 12 {
                hour24 = 0
            }
        } else {
            // PM: 12 PM = 12, 1-11 PM = 13-23
            if hour != 12 {
                hour24 = hour + 12
            }
        }
        
        return String(format: "%02d:%02d:00", hour24, minute)
    }
    
    /// Parse time string from HH:mm:ss format to hour/minute/isAM
    /// - Parameter timeString: Time string in HH:mm:ss or HH:mm format
    /// - Returns: Tuple of (hour: Int, minute: Int, isAM: Bool), or nil if parsing fails
    func parseTime(_ timeString: String) -> (hour: Int, minute: Int, isAM: Bool)? {
        let components = timeString.components(separatedBy: ":")
        guard components.count >= 2,
              let hour24 = Int(components[0]),
              let minute = Int(components[1]),
              hour24 >= 0 && hour24 < 24,
              minute >= 0 && minute < 60 else {
            return nil
        }
        
        var hour12: Int
        let isAM: Bool
        
        // Convert 24-hour to 12-hour format
        if hour24 == 0 {
            // 00:xx = 12:xx AM
            hour12 = 12
            isAM = true
        } else if hour24 < 12 {
            // 01-11:xx = 1-11:xx AM
            hour12 = hour24
            isAM = true
        } else if hour24 == 12 {
            // 12:xx = 12:xx PM
            hour12 = 12
            isAM = false
        } else {
            // 13-23:xx = 1-11:xx PM
            hour12 = hour24 - 12
            isAM = false
        }
        
        return (hour12, minute, isAM)
    }
}





