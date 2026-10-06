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

    /// Starts true: until the check has run the screen is "verifying", not "access denied".
    @Published var isVerifyingAdmin: Bool = true
    @Published var isAdmin: Bool = false
    @Published var fulfilledCount: Int = 0
    @Published var totalSavings: Double = 0
    @Published var activeRidesCount: Int = 0
    @Published var error: AppError?
    @Published var isLoading: Bool = false
    /// Set when the admin check could not be completed (offline, server error). That is not
    /// an answer about admin status, so the screen offers a retry instead of "Access Denied".
    @Published var verificationErrorMessage: String?
    /// Set when the dashboard figures could not be loaded
    @Published var statsErrorMessage: String?
    /// True once the figures have loaded; until then the tiles show a dash rather than 0
    @Published var hasLoadedStats: Bool = false

    // MARK: - Private Properties

    private let adminService = AdminService.shared
    private var hasVerified = false

    // MARK: - Computed Properties

    /// Formatted savings string (e.g. "$1,234")
    var formattedSavings: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD" // estimates are US dollars; the region must not relabel them
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalSavings)) ?? "$0"
    }

    // MARK: - Public Methods

    /// Verify admin access and load stats
    func verifyAdminAccess() async {
        guard !hasVerified else { return }

        isVerifyingAdmin = true
        error = nil
        verificationErrorMessage = nil
        defer { isVerifyingAdmin = false }

        do {
            try await adminService.verifyAdminStatus()
            hasVerified = true
            isAdmin = true
            await loadStats()
        } catch {
            isAdmin = false
            // verifyAdminStatus throws .unauthorized only for a confirmed "not an admin" (or no
            // session). Anything else is a network or server failure and must stay retryable.
            if let appError = error as? AppError, case .unauthorized = appError {
                self.error = appError
                AppLogger.error("security", "Non-admin accessed admin panel view")
            } else {
                self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
                verificationErrorMessage = "admin_verify_failed".localized
                AppLogger.error("admin", "Admin check failed: \(error.localizedDescription)")
            }
        }
    }

    /// Load admin dashboard statistics via RPC
    func loadStats() async {
        isLoading = true
        error = nil
        statsErrorMessage = nil
        defer { isLoading = false }

        do {
            let stats = try await adminService.fetchDashboardStats()
            fulfilledCount = stats.fulfilledCount
            totalSavings = stats.totalSavings
            activeRidesCount = stats.activeRidesCount
            hasLoadedStats = true
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            statsErrorMessage = "admin_stats_load_failed".localized
            AppLogger.error("admin", "Error loading stats: \(error.localizedDescription)")
        }
    }
}
