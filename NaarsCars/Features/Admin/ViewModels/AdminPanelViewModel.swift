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
    @Published var fulfilledCount: Int = 0
    @Published var totalSavings: Double = 0
    @Published var activeRidesCount: Int = 0
    @Published var error: AppError?
    @Published var isLoading: Bool = false

    // MARK: - Private Properties

    private let adminService = AdminService.shared
    private var hasVerified = false

    // MARK: - Computed Properties

    /// Formatted savings string (e.g. "$1,234")
    var formattedSavings: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalSavings)) ?? "$0"
    }

    // MARK: - Public Methods

    /// Verify admin access and load stats
    func verifyAdminAccess() async {
        guard !hasVerified else { return }

        isVerifyingAdmin = true
        error = nil
        defer { isVerifyingAdmin = false }

        do {
            try await adminService.verifyAdminStatus()
            hasVerified = true
            isAdmin = true
            await loadStats()
        } catch {
            self.error = error as? AppError ?? AppError.unauthorized
            isAdmin = false
            Log.security("Non-admin accessed admin panel view")
        }
    }

    /// Load admin dashboard statistics via RPC
    func loadStats() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let stats = try await adminService.fetchDashboardStats()
            fulfilledCount = stats.fulfilledCount
            totalSavings = stats.totalSavings
            activeRidesCount = stats.activeRidesCount
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            AppLogger.error("admin", "Error loading stats: \(error.localizedDescription)")
        }
    }
}
