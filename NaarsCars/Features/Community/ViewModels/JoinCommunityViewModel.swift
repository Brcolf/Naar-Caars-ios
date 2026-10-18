//
//  JoinCommunityViewModel.swift
//  NaarsCars
//
//  Joins a community with a typed invite code, or asks to join a public one
//

internal import Combine
import Foundation

enum JoinTarget: Equatable {
    case code(prefilled: String?)
    case publicCommunity(PublicCommunity)
}

@MainActor
final class JoinCommunityViewModel: ObservableObject {
    @Published var code: String
    @Published private(set) var preview: InvitePreview?
    @Published var heardAbout = ""
    @Published var joinReason = ""
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var result: JoinResult?

    let target: JoinTarget

    private let service: any CommunityServiceProtocol
    private let onResult: @MainActor (JoinResult) -> Void
    /// Cleared here, and only here, once the stored code is used or known to be dead (spec §3.7).
    private let pendingInviteStore: PendingInviteStore

    init(
        target: JoinTarget,
        service: any CommunityServiceProtocol = CommunityService.shared,
        onResult: @escaping @MainActor (JoinResult) -> Void = { _ in },
        pendingInviteStore: PendingInviteStore = PendingInviteStore()
    ) {
        self.target = target
        self.service = service
        self.onResult = onResult
        self.pendingInviteStore = pendingInviteStore
        if case .code(let prefilled) = target {
            self.code = prefilled ?? ""
        } else {
            self.code = ""
        }
    }

    var normalizedCode: String { CommunityInviteCode.normalize(code) }

    var isCodeTarget: Bool {
        if case .code = target { return true }
        return false
    }

    var publicCommunity: PublicCommunity? {
        if case .publicCommunity(let community) = target { return community }
        return nil
    }

    var communityName: String? {
        publicCommunity?.name ?? preview?.communityName
    }

    /// A public community always makes a pending row (`request_to_join_community`); a code follows
    /// the community's join policy.
    var requiresApproval: Bool {
        if publicCommunity != nil { return true }
        return preview?.requiresApproval ?? true
    }

    private var hasValidTarget: Bool {
        if publicCommunity != nil { return true }
        guard let preview else { return false }
        return preview.valid && preview.alreadyMember != true
    }

    var canSubmit: Bool {
        guard !isWorking, result == nil, hasValidTarget else { return false }
        let heard = heardAbout.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = joinReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = Constants.Community.answerMaxLength
        guard heard.count <= limit, reason.count <= limit else { return false }
        if requiresApproval { return !heard.isEmpty && !reason.isEmpty }
        return true
    }

    /// Looks a typed code up. A malformed code never reaches the server, where every failed
    /// attempt counts against the hourly limit.
    func validate() async {
        guard isCodeTarget, !isWorking, result == nil else { return }
        errorMessage = nil
        preview = nil
        let normalized = normalizedCode
        guard CommunityInviteCode.isWellFormed(normalized) else {
            errorMessage = "community_join_code_malformed".localized
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let answer = try await service.validateInvite(code: normalized)
            if answer.valid {
                preview = answer
                if answer.alreadyMember == true {
                    pendingInviteStore.clearIfMatches(normalized)
                    errorMessage = "community_join_already_member".localized
                }
            } else if answer.expired {
                pendingInviteStore.clearIfMatches(normalized)
                if let name = answer.communityName {
                    errorMessage = String(format: "community_join_expired_named".localized, name)
                } else {
                    errorMessage = "community_error_expired".localized
                }
            } else {
                pendingInviteStore.clearIfMatches(normalized)
                errorMessage = "community_error_invalid".localized
            }
        } catch let refusal as CommunityRPCError {
            clearStoredCodeIfDead(refusal, code: normalized)
            errorMessage = refusal.localizedMessage
        } catch {
            AppLogger.error("community", "validateInvite failed: \(error)")
            errorMessage = "community_error_generic".localized
        }
    }

    /// Redeems the code or asks to join. The result is reported in the same main-actor turn it is
    /// set, so a sheet that is swiped away afterwards loses nothing.
    func submit() async {
        guard !isWorking, result == nil, canSubmit else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        let limit = Constants.Community.answerMaxLength
        let heard = Validators.sanitizeUserInput(heardAbout, maxLength: limit)
        let reason = Validators.sanitizeUserInput(joinReason, maxLength: limit)
        let heardValue = heard.isEmpty ? nil : heard
        let reasonValue = reason.isEmpty ? nil : reason

        do {
            let joined: JoinResult
            if let community = publicCommunity {
                joined = try await service.requestToJoin(
                    communityId: community.id,
                    heardAbout: heardValue,
                    joinReason: reasonValue
                )
            } else {
                let code = normalizedCode
                joined = try await service.redeemInvite(
                    code: code,
                    heardAbout: heardValue,
                    joinReason: reasonValue
                )
                pendingInviteStore.clearIfMatches(code)
            }
            result = joined
            onResult(joined)
        } catch let refusal as CommunityRPCError {
            if publicCommunity == nil {
                clearStoredCodeIfDead(refusal, code: normalizedCode)
            }
            errorMessage = refusal.localizedMessage
        } catch {
            AppLogger.error("community", "join failed: \(error)")
            errorMessage = "community_error_generic".localized
        }
    }

    /// A refusal that says the code can never work for this account drops the stored copy. A
    /// network failure, `rate_limited`, `full` or `recently_rejected` keeps it for a later try.
    private func clearStoredCodeIfDead(_ refusal: CommunityRPCError, code: String) {
        switch refusal.code {
        case .invalid, .expired, .exhausted, .removed, .alreadyMember, .alreadyPending:
            pendingInviteStore.clearIfMatches(code)
        default:
            break
        }
    }
}
