//
//  BroadcastViewModel.swift
//  NaarsCars
//
//  ViewModel for sending an announcement to one community
//

import Foundation
internal import Combine

/// ViewModel for sending an announcement to one community (`send_community_broadcast`).
@MainActor
final class BroadcastViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var title: String = ""
    @Published var message: String = ""
    @Published var pinToNotifications: Bool = true
    @Published private(set) var isLoading: Bool = false
    /// The failure shown under the form; the typed announcement is kept.
    @Published var errorMessage: String?
    @Published var successMessage: String?

    /// The community the announcement goes to.
    let communityId: UUID
    let communityName: String

    // MARK: - Private Properties

    private let adminService: any AdminServiceProtocol
    private var successClearTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        communityId: UUID,
        communityName: String,
        adminService: any AdminServiceProtocol = AdminService.shared
    ) {
        self.communityId = communityId
        self.communityName = communityName
        self.adminService = adminService
    }

    // MARK: - Validation

    /// Both trimmed fields must be non-empty.
    func validate() -> Bool {
        errorMessage = nil

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = AppError.requiredFieldMissing.localizedDescription
            return false
        }

        return true
    }

    // MARK: - Actions

    /// Sends the announcement. One RPC per tap: returns at once while a send is in flight.
    /// On any failure the form is kept so the announcement can be sent later.
    func sendBroadcast() async {
        guard !isLoading else { return }
        guard validate() else { return }

        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageValue = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinned = pinToNotifications

        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }

        do {
            _ = try await adminService.sendBroadcast(
                communityId: communityId,
                title: titleValue,
                message: messageValue,
                pinToNotifications: pinned
            )

            HapticManager.success()
            successMessage = "admin_broadcast_success".localized

            // Clear form after success
            title = ""
            message = ""
            pinToNotifications = true

            // Clear success message after delay
            successClearTask?.cancel()
            successClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Constants.Timing.broadcastSuccessClearNanoseconds)
                guard !Task.isCancelled else { return }
                self?.successMessage = nil
            }
        } catch let error as AdminServiceError {
            switch error {
            case .broadcastDailyLimit:
                errorMessage = "admin_broadcast_daily_limit".localized(with: communityName)
            case .notCommunityAdmin:
                errorMessage = "community_pending_not_admin".localized
            }
            AppLogger.warning("admin", "Announcement to \(communityId) refused: \(error)")
        } catch {
            errorMessage = "community_error_generic".localized
            AppLogger.error("admin", "Error sending announcement: \(error.localizedDescription)")
        }
    }
}
