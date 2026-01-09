//
//  CreateFavorViewModel.swift
//  NaarsCars
//
//  ViewModel for creating a new favor request
//

import Foundation
internal import Combine

/// ViewModel for creating a new favor request
@MainActor
final class CreateFavorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var location: String = ""
    @Published var duration: FavorDuration = .notSure
    @Published var requirements: String = ""
    @Published var date: Date = Date()
    @Published var time: String = ""
    @Published var gift: String = ""
    
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Private Properties
    
    private let favorService = FavorService.shared
    private let authService = AuthService.shared
    
    // MARK: - Public Methods
    
    /// Validate form fields
    /// - Returns: Error message if validation fails, nil if valid
    func validateForm() -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Title is required"
        }
        
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Location is required"
        }
        
        // Validate date is not in the past
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selectedDate = calendar.startOfDay(for: date)
        
        if selectedDate < today {
            return "Date cannot be in the past"
        }
        
        // Validate time format if provided
        if !time.isEmpty {
            let timePattern = #"^([0-1]?[0-9]|2[0-3]):[0-5][0-9](:([0-5][0-9]))?$"#
            if time.range(of: timePattern, options: .regularExpression) == nil {
                return "Time must be in format HH:mm or HH:mm:ss"
            }
        }
        
        return nil
    }
    
    /// Create the favor request
    /// - Returns: Created favor if successful
    /// - Throws: AppError if creation fails
    func createFavor() async throws -> Favor {
        // Validate form
        if let error = validateForm() {
            throw AppError.invalidInput(error)
        }
        
        // Get current user ID
        guard let userId = authService.currentUserId else {
            throw AppError.authenticationRequired
        }
        
        // Format time to HH:mm:ss if needed
        let formattedTime = time.isEmpty ? nil : formatTime(time)
        
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let favor = try await favorService.createFavor(
                userId: userId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                duration: duration,
                requirements: requirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : requirements.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                time: formattedTime,
                gift: gift.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : gift.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            return favor
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



