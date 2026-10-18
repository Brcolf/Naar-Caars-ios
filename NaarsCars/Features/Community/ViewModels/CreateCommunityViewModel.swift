//
//  CreateCommunityViewModel.swift
//  NaarsCars
//
//  Creates a community (create_community) and, for platform admins, makes it public
//

internal import Combine
import Foundation

@MainActor
final class CreateCommunityViewModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    /// New communities default to manual approval.
    @Published var requiresApproval = true
    /// Shown to platform admins only.
    @Published var allowGuests = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    /// The last refusal from the server; the limit-request flow reads `.code == .ownedLimit`.
    @Published private(set) var lastRefusal: CommunityRPCError?

    let showsGuestToggle: Bool

    private let service: any CommunityServiceProtocol
    private let adminService: any CommunityAdminServiceProtocol

    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        adminService: any CommunityAdminServiceProtocol = CommunityService.shared,
        isPlatformAdmin: Bool = AuthService.shared.currentProfile?.isAdmin == true
    ) {
        self.service = service
        self.adminService = adminService
        self.showsGuestToggle = isPlatformAdmin
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSubmit: Bool {
        !isSubmitting
            && Constants.Community.nameLength.contains(trimmedName.count)
            && trimmedDescription.count <= Constants.Community.descriptionMaxLength
    }

    func submit() async -> CreatedCommunity? {
        guard !isSubmitting, canSubmit else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        lastRefusal = nil

        let cleanName = Validators.sanitizeUserInput(name, maxLength: Constants.Community.nameLength.upperBound)
        let cleanDescription = Validators.sanitizeUserInput(description, maxLength: Constants.Community.descriptionMaxLength)
        let policy: CommunityJoinPolicy = requiresApproval ? .approve : .invite
        let wantsPublic = allowGuests && showsGuestToggle

        let created: CreatedCommunity
        do {
            created = try await service.createCommunity(
                name: cleanName,
                description: cleanDescription.isEmpty ? nil : cleanDescription,
                joinPolicy: policy
            )
        } catch let refusal as CommunityRPCError {
            lastRefusal = refusal
            errorMessage = refusal.localizedMessage
            return nil
        } catch {
            AppLogger.error("community", "createCommunity failed: \(error)")
            errorMessage = "community_error_generic".localized
            return nil
        }

        if wantsPublic {
            do {
                try await adminService.setCommunityPublic(communityId: created.communityId, isPublic: true)
            } catch {
                AppLogger.error("community", "setCommunityPublic after create failed: \(error)")
                errorMessage = "community_create_public_failed".localized
            }
        }
        return created
    }
}
