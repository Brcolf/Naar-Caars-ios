//
//  CommunityInviteViewModel.swift
//  NaarsCars
//
//  Creates, lists and revokes the caller's invite codes for one community
//

internal import Combine
import Foundation

@MainActor
final class CommunityInviteViewModel: ObservableObject {
    @Published private(set) var invite: CommunityInvite?
    @Published private(set) var liveCodes: [CommunityInviteRow] = []
    /// Admin only: 1...Constants.Community.adminInviteMaxUses
    @Published var maxUses = 1
    /// Admin only: one of `Constants.Community.inviteExpiryDayChoices`
    @Published var expiryDays = Constants.Community.memberInviteLifetimeDays
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    let communityId: UUID
    let communityName: String
    let isAdmin: Bool

    private let service: any CommunityServiceProtocol
    private let authService: any AuthServiceProtocol
    private let now: () -> Date

    init(
        communityId: UUID,
        communityName: String,
        isAdmin: Bool,
        service: any CommunityServiceProtocol = CommunityService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.communityId = communityId
        self.communityName = communityName
        self.isAdmin = isAdmin
        self.service = service
        self.authService = authService
        self.now = now
    }

    var displayedCode: String? { invite?.code ?? liveCodes.first?.code }

    var shareMessage: String? {
        guard let code = displayedCode else { return nil }
        return String(
            format: "community_invite_share_message".localized,
            communityName,
            Constants.URLs.appStore,
            InviteCodeFormatter.formatCode(code)
        )
    }

    /// Lists the caller's live codes; when there are none, creates one.
    func prepare() async {
        await loadLiveCodes()
        if liveCodes.isEmpty && invite == nil && errorMessage == nil {
            await createCode()
        }
    }

    /// Always sends an expiry, so a role the client has wrong is harmless: the server clamps a
    /// member to one use and 7 days, and an admin call needs an expiry.
    func createCode() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        let current = now()
        let uses: Int?
        let expiry: Date
        if isAdmin {
            uses = max(1, min(maxUses, Constants.Community.adminInviteMaxUses))
            // The margin keeps a 90-day choice inside the server's `now() + 90 days` check when
            // the phone's clock runs a little ahead.
            expiry = current.addingTimeInterval(TimeInterval(expiryDays) * 86_400 - 300)
        } else {
            uses = nil
            expiry = current.addingTimeInterval(TimeInterval(Constants.Community.memberInviteLifetimeDays) * 86_400)
        }

        do {
            let created = try await service.createInvite(communityId: communityId, maxUses: uses, expiresAt: expiry)
            invite = created
            await refreshLiveCodes()
        } catch let refusal as CommunityRPCError {
            errorMessage = refusal.localizedMessage
        } catch {
            AppLogger.error("community", "createInvite failed: \(error)")
            errorMessage = "community_error_generic".localized
        }
    }

    func loadLiveCodes() async {
        await refreshLiveCodes()
    }

    func revoke(_ row: CommunityInviteRow) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await service.revokeInvite(inviteId: row.id)
            liveCodes.removeAll { $0.id == row.id }
            if invite?.inviteId == row.id { invite = nil }
        } catch let refusal as CommunityRPCError {
            errorMessage = refusal.localizedMessage
        } catch {
            AppLogger.error("community", "revokeInvite failed: \(error)")
            errorMessage = "community_error_generic".localized
        }
    }

    /// A failed list read leaves the codes as they were and shows nothing: the list is a convenience.
    private func refreshLiveCodes() async {
        guard let userId = await SignedInUser.resolveId(authService: authService) else { return }
        do {
            let rows = try await service.fetchLiveInvites(communityId: communityId, createdBy: userId)
            let current = now()
            liveCodes = rows.filter { $0.isLive(at: current) }
        } catch {
            AppLogger.warning("community", "fetchLiveInvites failed: \(error)")
        }
    }
}
