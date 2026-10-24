//
//  OwnedLimitRequestViewModel.swift
//  NaarsCars
//
//  Asks a platform admin to raise the member's owned-community limit (request_owned_community_limit)
//

internal import Combine
import Foundation

@MainActor
final class OwnedLimitRequestViewModel: ObservableObject {
    @Published var requested: Int
    @Published var reason = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let currentMax: Int
    private let service: any CommunityServiceProtocol

    init(currentMax: Int, service: any CommunityServiceProtocol = CommunityService.shared) {
        self.currentMax = currentMax
        self.service = service
        self.requested = Self.range(currentMax: currentMax).lowerBound
    }

    /// False at or above the ceiling a platform admin can approve.
    static func canRequestMore(currentMax: Int) -> Bool {
        currentMax < Constants.Community.limitRequestRange.upperBound
    }

    /// Total for every `currentMax`: never builds a range whose lower bound exceeds its upper bound.
    static func range(currentMax: Int) -> ClosedRange<Int> {
        let r = Constants.Community.limitRequestRange
        let lower = min(max(r.lowerBound, currentMax + 1), r.upperBound)
        return lower...r.upperBound
    }

    var range: ClosedRange<Int> { Self.range(currentMax: currentMax) }

    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSubmit: Bool {
        !isSubmitting
            && Self.canRequestMore(currentMax: currentMax)
            && (1...Constants.Community.answerMaxLength).contains(trimmedReason.count)
            && range.contains(requested)
    }

    /// Returns true when the request was recorded.
    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        let cleanReason = Validators.sanitizeUserInput(reason, maxLength: Constants.Community.answerMaxLength)
        do {
            _ = try await service.requestOwnedCommunityLimit(requested: requested, reason: cleanReason)
            HapticManager.success()
            return true
        } catch let refusal as CommunityRPCError {
            errorMessage = refusal.localizedMessage
            return false
        } catch {
            AppLogger.error("community", "requestOwnedCommunityLimit failed: \(error)")
            errorMessage = "community_error_generic".localized
            return false
        }
    }
}
