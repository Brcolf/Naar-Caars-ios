//
//  LeaveCommunitySheet.swift
//  NaarsCars
//
//  Confirms leaving a community (with what happens to open requests and claims there),
//  or withdrawing a request to join
//

import SwiftUI

struct LeaveCommunitySheet: View {
    @Environment(\.dismiss) private var dismiss

    let membership: CommunityMembership
    let plan: LeavePlan
    let isOnlyActiveCommunity: Bool
    let onConfirm: () -> Void

    init(
        membership: CommunityMembership,
        plan: LeavePlan,
        isOnlyActiveCommunity: Bool,
        onConfirm: @escaping () -> Void
    ) {
        self.membership = membership
        self.plan = plan
        self.isOnlyActiveCommunity = isOnlyActiveCommunity
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    Text(title)
                        .font(.naarsTitle3)
                        .foregroundColor(.naarsTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.naarsBody)
                                .foregroundColor(.naarsTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: Constants.Spacing.sm) {
                        SecondaryButton(title: confirmTitle, isDestructive: true) {
                            onConfirm()
                        }
                        .accessibilityIdentifier("community.leave.confirm")

                        Button("common_cancel".localized) { dismiss() }
                            .font(.naarsHeadline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("community.leave.cancel")
                    }
                    .padding(.top, Constants.Spacing.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color.naarsBackground)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Copy

    private var title: String {
        switch plan {
        case .withdrawRequest:
            return String(format: "community_withdraw_title".localized, membership.name)
        case .leave, .closesCommunity:
            return String(format: "community_leave_title".localized, membership.name)
        }
    }

    private var confirmTitle: String {
        switch plan {
        case .withdrawRequest: return "community_withdraw_confirm".localized
        case .leave, .closesCommunity: return "community_leave_confirm".localized
        }
    }

    /// Spec §2.1 rule 13: only the non-zero counts, or "nothing open"; always what stays.
    private var lines: [String] {
        let consequences: LeaveConsequences
        switch plan {
        case .withdrawRequest:
            return []
        case .leave(let value), .closesCommunity(let value):
            consequences = value
        }

        var result: [String] = []
        if case .closesCommunity = plan {
            result.append(String(format: "community_leave_closes".localized, membership.name))
        }
        if consequences.isEmpty {
            result.append("community_leave_nothing".localized)
        } else {
            if consequences.reopened > 0 {
                result.append(Self.count(consequences.reopened, key: "community_leave_reopened"))
            }
            if consequences.removed > 0 {
                result.append(Self.count(consequences.removed, key: "community_leave_removed"))
            }
            if consequences.cancelled > 0 {
                result.append(Self.count(consequences.cancelled, key: "community_leave_cancelled"))
            }
        }
        result.append("community_leave_keeps".localized)
        if isOnlyActiveCommunity {
            result.append("community_leave_only_community".localized)
        }
        return result
    }

    private static func count(_ value: Int, key: String) -> String {
        String(format: (value == 1 ? "\(key)_one" : "\(key)_other").localized, value)
    }
}

#if DEBUG
private let previewMembership = PreviewCommunityService.membership(name: "Ballard Neighbors", role: .member)

#Preview("Counts") {
    Color.naarsBackground.sheet(isPresented: .constant(true)) {
        LeaveCommunitySheet(
            membership: previewMembership,
            plan: .leave(LeaveConsequences(reopened: 1, removed: 2, cancelled: 1)),
            isOnlyActiveCommunity: false,
            onConfirm: {}
        )
    }
}

#Preview("Nothing open") {
    Color.naarsBackground.sheet(isPresented: .constant(true)) {
        LeaveCommunitySheet(
            membership: previewMembership,
            plan: .leave(.none),
            isOnlyActiveCommunity: true,
            onConfirm: {}
        )
    }
}

#Preview("Closes") {
    Color.naarsBackground.sheet(isPresented: .constant(true)) {
        LeaveCommunitySheet(
            membership: PreviewCommunityService.membership(name: "Ballard Neighbors", role: .owner, memberCount: 1),
            plan: .closesCommunity(LeaveConsequences(reopened: 0, removed: 1, cancelled: 0)),
            isOnlyActiveCommunity: false,
            onConfirm: {}
        )
    }
}

#Preview("Withdraw") {
    Color.naarsBackground.sheet(isPresented: .constant(true)) {
        LeaveCommunitySheet(
            membership: PreviewCommunityService.membership(name: "Fremont Families", status: .pending),
            plan: .withdrawRequest,
            isOnlyActiveCommunity: false,
            onConfirm: {}
        )
    }
}
#endif
