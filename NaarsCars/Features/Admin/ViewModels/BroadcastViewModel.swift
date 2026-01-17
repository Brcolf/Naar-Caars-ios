//
//  BroadcastViewModel.swift
//  NaarsCars
//
//  ViewModel for sending broadcast announcements
//

import Foundation
internal import Combine

/// ViewModel for sending broadcast announcements
@MainActor
final class BroadcastViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var pinToNotifications: Bool = true
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var successMessage: String?
    
    // MARK: - Private Properties
    
    private let adminService = AdminService.shared
    
    // MARK: - Validation
    
    /// Validate broadcast form
    /// - Returns: True if valid, false otherwise
    func validate() -> Bool {
        error = nil
        
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = AppError.requiredFieldMissing
            return false
        }
        
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = AppError.requiredFieldMissing
            return false
        }
        
        return true
    }
    
    // MARK: - Actions
    
    /// Send broadcast announcement
    func sendBroadcast() async {
        guard validate() else {
            return
        }
        
        isLoading = true
        error = nil
        successMessage = nil
        defer { isLoading = false }
        
        do {
            try await adminService.sendBroadcast(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                pinToNotifications: pinToNotifications
            )
            
            successMessage = "Broadcast sent successfully!"
            
            // Clear form after success
            title = ""
            message = ""
            pinToNotifications = true
            
            // Clear success message after delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    successMessage = nil
                }
            }
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            print("🔴 [BroadcastViewModel] Error sending broadcast: \(error.localizedDescription)")
        }
    }
}


