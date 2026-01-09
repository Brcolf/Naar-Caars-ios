//
//  AdminPanelViewModel.swift
//  NaarsCars
//
//  ViewModel for admin panel dashboard
//

import Foundation
internal import Combine

/// ViewModel for admin panel dashboard
@MainActor
final class AdminPanelViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isVerifyingAdmin: Bool = false
    @Published var isAdmin: Bool = false
    @Published var pendingCount: Int = 0
    @Published var totalMembers: Int = 0
    @Published var activeMembers: Int = 0
    @Published var error: AppError?
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    private let adminService = AdminService.shared
    private var hasVerified = false // Track if we've already verified to prevent re-verification
    
    // MARK: - Public Methods
    
    /// Verify admin access and load stats
    func verifyAdminAccess() async {
        // Only verify once
        guard !hasVerified else { return }
        
        isVerifyingAdmin = true
        error = nil
        hasVerified = true
        defer { isVerifyingAdmin = false }
        
        do {
            // Verify admin status
            try await adminService.verifyAdminStatus()
            isAdmin = true
            
            // Load stats
            await loadStats()
        } catch {
            self.error = error as? AppError ?? AppError.unauthorized
            isAdmin = false
            Log.security("Non-admin accessed admin panel view")
        }
    }
    
    /// Load admin statistics
    func loadStats() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let stats = try await adminService.fetchAdminStats()
            pendingCount = stats.pendingCount
            totalMembers = stats.totalMembers
            activeMembers = stats.activeMembers
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            print("🔴 [AdminPanelViewModel] Error loading stats: \(error.localizedDescription)")
        }
    }
}

