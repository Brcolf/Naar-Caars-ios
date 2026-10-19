//
//  PendingMembersView.swift
//  NaarsCars
//
//  Requests to join one community, with approve and decline
//

import SwiftUI

/// A decision waiting for its confirmation alert.
private struct PendingDecision: Identifiable {
    let member: CommunityMember
    let approve: Bool
    var id: String { "\(member.id.uuidString)-\(approve)" }
}

/// The name shown for an applicant; a blank profile name reads as "Former member".
private func applicantDisplayName(_ member: CommunityMember) -> String {
    let trimmed = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "community_former_member".localized : trimmed
}

/// Requests to join one community. No NavigationStack: always pushed (Profile tab, Admin panel).
struct PendingMembersView: View {
    @StateObject private var viewModel: PendingMembersViewModel
    @State private var decision: PendingDecision?

    init(target: PendingMembersTarget) {
        _viewModel = StateObject(wrappedValue: PendingMembersViewModel(target: target))
    }

    init(viewModel: @autoclosure @escaping () -> PendingMembersViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        Group {
            switch viewModel.access {
            case .notAdmin:
                notAdminState
            case .checking, .allowed:
                if viewModel.applicants.isEmpty {
                    if viewModel.isLoading || viewModel.access == .checking && viewModel.loadError == nil {
                        skeleton
                    } else if let loadError = viewModel.loadError {
                        ErrorView(error: loadError) {
                            Task { await viewModel.load() }
                        }
                    } else {
                        EmptyStateView(
                            icon: "person.badge.clock",
                            title: "community_pending_empty_title".localized,
                            message: "community_pending_empty_body".localized
                        )
                    }
                } else {
                    list
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("community_pending_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .alert(
            alertTitle,
            isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }),
            presenting: decision
        ) { pending in
            Button("common_cancel".localized, role: .cancel) {}
            Button(
                pending.approve ? "community_pending_approve".localized : "community_pending_decline".localized,
                role: pending.approve ? nil : .destructive
            ) {
                let member = pending.member
                let approve = pending.approve
                Task {
                    if approve {
                        await viewModel.approve(member)
                    } else {
                        await viewModel.reject(member)
                    }
                }
            }
        } message: { pending in
            Text(pending.approve ? "community_pending_approve_body".localized : "community_pending_decline_body".localized)
        }
        .errorBanner(message: $viewModel.actionErrorMessage)
    }

    private var alertTitle: String {
        guard let decision else { return "" }
        let key = decision.approve ? "community_pending_approve_title" : "community_pending_decline_title"
        return String(format: key.localized, applicantDisplayName(decision.member))
    }

    // MARK: - States

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                if let name = viewModel.communityName {
                    Text(name)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(viewModel.applicants) { member in
                    PendingMemberCard(
                        member: member,
                        showsDetailLink: viewModel.showsContact,
                        viewModel: viewModel,
                        isActionDisabled: viewModel.actingOnUserId != nil,
                        onApprove: { decision = PendingDecision(member: member, approve: true) },
                        onDecline: { decision = PendingDecision(member: member, approve: false) }
                    )
                }
            }
            .padding()
        }
        .refreshable { await viewModel.load() }
    }

    private var notAdminState: some View {
        VStack(spacing: Constants.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("community_pending_not_admin".localized)
                .font(.naarsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("community.pending.notAdmin")
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                        HStack(spacing: Constants.Spacing.md) {
                            SkeletonCircle(size: 44)
                            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                                SkeletonRectangle(width: 140, height: 16)
                                SkeletonRectangle(width: 90, height: 12)
                            }
                            Spacer()
                        }
                        SkeletonRectangle(height: 40)
                        SkeletonRectangle(height: 44, cornerRadius: Constants.Radius.button)
                    }
                    .cardStyle()
                }
            }
            .padding()
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

private struct PendingMemberCard: View {
    let member: CommunityMember
    let showsDetailLink: Bool
    @ObservedObject var viewModel: PendingMembersViewModel
    let isActionDisabled: Bool
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            if showsDetailLink {
                NavigationLink {
                    PendingMemberDetailView(member: member, viewModel: viewModel)
                } label: {
                    HStack {
                        PendingMemberHeader(member: member)
                        Image(systemName: "chevron.right")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("community.pending.detailLink")
            } else {
                PendingMemberHeader(member: member)
            }

            PendingMemberAnswers(member: member)

            PendingMemberActions(
                member: member,
                isActionDisabled: isActionDisabled,
                isActing: viewModel.actingOnUserId == member.id,
                onApprove: onApprove,
                onDecline: onDecline
            )
        }
        .cardStyle()
        .accessibilityIdentifier("community.pending.row")
    }
}

private struct PendingMemberHeader: View {
    let member: CommunityMember

    var body: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.md) {
            AvatarView(imageUrl: member.avatarUrl, name: applicantDisplayName(member), size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(applicantDisplayName(member))
                    .font(.naarsHeadline)
                    .foregroundColor(.primary)
                if let car = member.car, !car.isEmpty {
                    Label(car, systemImage: "car.fill")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                if let inviter = member.invitedByName, !inviter.isEmpty {
                    Text(String(format: "community_pending_invited_by".localized, inviter))
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                Text(String(format: "community_pending_applied".localized, member.joinedAt.timeAgo))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PendingMemberAnswers: View {
    let member: CommunityMember

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            answer(label: "admin_heard_about_label".localized, text: member.heardAbout)
            answer(label: "admin_join_reason_label".localized, text: member.joinReason)
        }
    }

    @ViewBuilder
    private func answer(label: String, text: String?) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                Text(label)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.naarsBody)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct PendingMemberActions: View {
    let member: CommunityMember
    let isActionDisabled: Bool
    let isActing: Bool
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Constants.Spacing.md) { buttons }
            VStack(spacing: Constants.Spacing.sm) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        SecondaryButton(
            title: "community_pending_decline".localized,
            action: onDecline,
            isDisabled: isActionDisabled,
            isDestructive: true
        )
        .accessibilityLabel(String(format: "community_pending_decline_title".localized, applicantDisplayName(member)))
        .accessibilityIdentifier("community.pending.decline")
        PrimaryButton(
            title: "community_pending_approve".localized,
            action: onApprove,
            isLoading: isActing,
            isDisabled: isActionDisabled
        )
        .accessibilityLabel(String(format: "community_pending_approve_title".localized, applicantDisplayName(member)))
        .accessibilityIdentifier("community.pending.approve")
    }
}

// MARK: - Detail

/// One applicant, with the email and phone a platform admin may read.
struct PendingMemberDetailView: View {
    let member: CommunityMember
    @ObservedObject var viewModel: PendingMembersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var decision: PendingDecision?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    PendingMemberHeader(member: member)
                    PendingMemberAnswers(member: member)
                }
                .cardStyle()

                if let contact = viewModel.contacts[member.id], contact.email != nil || contact.phoneNumber != nil {
                    contactCard(contact)
                }

                PendingMemberActions(
                    member: member,
                    isActionDisabled: viewModel.actingOnUserId != nil,
                    isActing: viewModel.actingOnUserId == member.id,
                    onApprove: { decision = PendingDecision(member: member, approve: true) },
                    onDecline: { decision = PendingDecision(member: member, approve: false) }
                )
            }
            .padding()
        }
        .background(Color.naarsBackground)
        .navigationTitle(applicantDisplayName(member))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadContact(for: member) }
        .onChange(of: viewModel.applicants.contains { $0.id == member.id }) { _, stillListed in
            if !stillListed { dismiss() }
        }
        .alert(
            alertTitle,
            isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }),
            presenting: decision
        ) { pending in
            Button("common_cancel".localized, role: .cancel) {}
            Button(
                pending.approve ? "community_pending_approve".localized : "community_pending_decline".localized,
                role: pending.approve ? nil : .destructive
            ) {
                let member = pending.member
                let approve = pending.approve
                Task {
                    if approve {
                        await viewModel.approve(member)
                    } else {
                        await viewModel.reject(member)
                    }
                }
            }
        } message: { pending in
            Text(pending.approve ? "community_pending_approve_body".localized : "community_pending_decline_body".localized)
        }
        .errorBanner(message: $viewModel.actionErrorMessage)
        .accessibilityIdentifier("community.pending.detail")
    }

    private var alertTitle: String {
        guard let decision else { return "" }
        let key = decision.approve ? "community_pending_approve_title" : "community_pending_decline_title"
        return String(format: key.localized, applicantDisplayName(decision.member))
    }

    private func contactCard(_ contact: ApplicantContact) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text("community_pending_contact".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let email = contact.email, !email.isEmpty {
                contactRow(icon: "envelope.fill", label: "auth_email_label".localized, value: email)
            }
            if let phone = contact.phoneNumber, !phone.isEmpty {
                contactRow(icon: "phone.fill", label: "profile_phone_number".localized, value: phone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func contactRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(.naarsPrimary)
                .accessibilityHidden(true)
            Text(value)
                .font(.naarsBody)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum PendingMembersPreview {
    static func viewModel(
        members: [CommunityMember] = PreviewCommunityService.sampleApplicants,
        platformAdmin: Bool = true,
        memberRole: Bool = false
    ) -> PendingMembersViewModel {
        let service = PreviewCommunityService()
        service.members = members
        let context = CommunityContext(
            service: service,
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { platformAdmin }
        )
        context.debugSetMemberships(PreviewCommunityService.sampleMemberships)
        // Seattle is a member-role membership; Ballard is owned.
        let row = PreviewCommunityService.sampleMemberships[memberRole ? 0 : 1]
        return PendingMembersViewModel(
            target: .community(row.communityId, name: row.name),
            adminService: service,
            communityContext: context,
            contactFetcher: service,
            refreshBadges: {}
        )
    }
}

#Preview("List") {
    NavigationStack {
        PendingMembersView(viewModel: PendingMembersPreview.viewModel())
    }
}

#Preview("Empty") {
    NavigationStack {
        PendingMembersView(viewModel: PendingMembersPreview.viewModel(members: []))
    }
}

#Preview("Not admin") {
    NavigationStack {
        PendingMembersView(viewModel: PendingMembersPreview.viewModel(platformAdmin: false, memberRole: true))
    }
}

#Preview("Detail with contact") {
    NavigationStack {
        PendingMemberDetailView(
            member: PreviewCommunityService.sampleApplicants[0],
            viewModel: PendingMembersPreview.viewModel()
        )
    }
}
#endif
