//
//  AccountDeletionCommunityCheck.swift
//  NaarsCars
//
//  Which communities deleting this account closes (decision A3)
//

import Foundation

/// The account-deletion warning's list (decision A3). The server applies A3 inside
/// `delete_user_account` whatever this says (20261017_0004 STEP A); this only decides what the
/// warning names before the final confirmation.
enum AccountDeletionCommunityCheck {
    /// Communities the server will archive when this account is deleted (A3, 20261017_0004 STEP A): active owner memberships,
    /// not the default community (A3 + INV-L1), where no other active owner and no active admin is among the members.
    /// A members fetch that fails counts the community in: the warning errs on the side of telling.
    static func communitiesClosed(
        byDeleting userId: UUID,
        memberships: [CommunityMembership],
        fetchActiveMembers: (UUID) async throws -> [CommunityMember]
    ) async -> [CommunityMembership] {
        let owned = memberships.filter { $0.role == .owner && $0.status == .active && !$0.isDefault }
        var closed: [CommunityMembership] = []
        for membership in owned {
            do {
                let members = try await fetchActiveMembers(membership.communityId)
                let successorExists = members.contains { member in
                    member.id != userId
                        && member.status == .active
                        && (member.role == .owner || member.role == .admin)
                }
                if !successorExists {
                    closed.append(membership)
                }
            } catch {
                AppLogger.warning("profile", "Deletion check could not read members of \(membership.communityId): \(error.localizedDescription)")
                closed.append(membership)
            }
        }
        return closed
    }
}
