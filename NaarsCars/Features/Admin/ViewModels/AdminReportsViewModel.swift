//
//  AdminReportsViewModel.swift
//  NaarsCars
//
//  ViewModel for the admin content-report queue
//

import Foundation
internal import Combine

/// Loads reports and applies moderation actions for AdminReportsView
@MainActor
final class AdminReportsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var reports: [AdminReport] = []
    @Published var isLoading = false
    @Published var isSubmittingAction = false
    @Published var errorAlertMessage: String?

    // MARK: - Private Properties

    private let moderationService = AdminModerationService.shared

    // MARK: - Public Methods

    func loadReports(status: String?) async {
        isLoading = true
        do {
            reports = try await moderationService.fetchReports(status: status)
        } catch {
            errorAlertMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Apply a moderation action, let the caller clear its sheet, then reload the list.
    /// `onModerated` runs after the server call succeeds and before the reload (same order as before).
    func moderate(
        reportId: UUID,
        action: String,
        notes: String?,
        reloadStatus: String?,
        onModerated: @MainActor () -> Void
    ) async {
        isSubmittingAction = true
        do {
            try await moderationService.moderateContent(
                reportId: reportId,
                action: action,
                notes: notes
            )
            onModerated()
            await loadReports(status: reloadStatus)
        } catch {
            errorAlertMessage = error.localizedDescription
        }
        isSubmittingAction = false
    }
}
