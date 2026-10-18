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
    /// not the default community (A3 + INV-L1), where no other active, unbanned owner and no active, unbanned admin is among the members.
    /// A members fetch that fails counts the community in: the warning errs on the side of telling.
    ///
    /// `get_community_members` returns banned members to a community admin and `CommunityMember` carries no banned flag,
    /// while STEP A skips banned owners and admins. So the possible successors are confirmed through
    /// `fetchUnbannedMemberIds`, which returns the ids among them that are not banned; a candidate it does not return,
    /// or a lookup that fails, is no successor.
    static func communitiesClosed(
        byDeleting userId: UUID,
        memberships: [CommunityMembership],
        fetchActiveMembers: (UUID) async throws -> [CommunityMember],
        fetchUnbannedMemberIds: (_ communityId: UUID, _ candidates: [CommunityMember]) async throws -> Set<UUID>
    ) async -> [CommunityMembership] {
        let owned = memberships.filter { $0.role == .owner && $0.status == .active && !$0.isDefault }
        var closed: [CommunityMembership] = []
        for membership in owned {
            do {
                let members = try await fetchActiveMembers(membership.communityId)
                let candidates = members.filter { member in
                    member.id != userId
                        && member.status == .active
                        && (member.role == .owner || member.role == .admin)
                }
                var successorExists = false
                if !candidates.isEmpty {
                    let unbanned = try await fetchUnbannedMemberIds(membership.communityId, candidates)
                    successorExists = candidates.contains { unbanned.contains($0.id) }
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
