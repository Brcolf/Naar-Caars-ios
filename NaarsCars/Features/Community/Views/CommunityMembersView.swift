//
//  CommunityMembersView.swift
//  NaarsCars
//
//  One community's members and removed members, for its owners and admins
//

import AuthenticationServices
import SwiftUI

/// Which community's members the screen shows. `highlightTransfer` adds the "choose who becomes
/// the owner" card (the last owner leaving).
struct CommunityMembersTarget: Hashable {
    let communityId: UUID
    let communityName: String?
    var highlightTransfer = false
}

/// Members and removed members. No NavigationStack: always pushed (Admin panel, My communities).
struct CommunityMembersView: View {
    let target: CommunityMembersTarget
    @StateObject private var viewModel: CommunityMembersViewModel

    init(
        target: CommunityMembersTarget,
        viewModel: @autoclosure @escaping () -> CommunityMembersViewModel? = nil
    ) {
        self.target = target
        _viewModel = StateObject(wrappedValue: viewModel() ?? CommunityMembersViewModel(
            communityId: target.communityId,
            communityName: target.communityName
        ))
    }

    var body: some View {
        Group {
            switch viewModel.access {
            case .notAdmin:
                notAdminState
            case .checking, .allowed:
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("community_members_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CommunityMember.self) { member in
            CommunityMemberDetailView(member: member, viewModel: viewModel)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.list) { _, _ in
            Task { await viewModel.load() }
        }
        .toast(message: $viewModel.toastMessage)
        .errorBanner(message: $viewModel.actionErrorMessage)
    }

    // MARK: - States

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                if let name = viewModel.communityName {
                    Text(name)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }

                if target.highlightTransfer && viewModel.list == .active {
                    transferBanner
                }

                Picker("community_members_title".localized, selection: $viewModel.list) {
                    Text("community_members_segment_active".localized).tag(CommunityMembersList.active)
                    Text("community_members_segment_removed".localized).tag(CommunityMembersList.removed)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("community.members.segment")

                rows
            }
            .padding()
        }
        .searchable(text: $viewModel.query, prompt: "community_members_search".localized)
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.members.isEmpty {
            if viewModel.isLoading || (viewModel.access == .checking && viewModel.loadError == nil) {
                skeleton
            } else if let loadError = viewModel.loadError {
                ErrorView(error: loadError) {
                    Task { await viewModel.load() }
                }
            } else {
                EmptyStateView(
                    icon: viewModel.list == .active ? "person.2" : "person.crop.circle.badge.xmark",
                    title: viewModel.list == .active
                        ? "community_members_empty".localized
                        : "community_members_removed_empty".localized,
                    message: ""
                )
                .accessibilityIdentifier("community.members.empty")
            }
        } else if viewModel.filteredMembers.isEmpty {
            ContentUnavailableView.search(text: viewModel.query)
        } else {
            ForEach(viewModel.filteredMembers) { member in
                NavigationLink(value: member) {
                    CommunityMemberRow(member: member, isRemovedList: viewModel.list == .removed)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("community.members.row")
            }
        }
    }

    private var transferBanner: some View {
        Label("community_members_transfer_banner".localized, systemImage: "crown.fill")
            .font(.naarsBody)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .accessibilityIdentifier("community.members.transferBanner")
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
        .accessibilityIdentifier("community.members.notAdmin")
    }

    private var skeleton: some View {
        VStack(spacing: Constants.Spacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: Constants.Spacing.md) {
                    SkeletonCircle(size: 40)
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        SkeletonRectangle(width: 150, height: 16)
                        SkeletonRectangle(width: 90, height: 12)
                    }
                    Spacer()
                }
                .cardStyle()
            }
        }
        .disabled(true)
        .accessibilityHidden(true)
    }
}

// MARK: - Row

/// The role chip for an owner or admin; nil for a member.
func communityMemberRoleText(_ role: CommunityRole) -> String? {
    switch role {
    case .owner: return "community_role_owner".localized
    case .admin: return "community_role_admin".localized
    case .member: return nil
    }
}

private struct CommunityMemberRow: View {
    let member: CommunityMember
    let isRemovedList: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the avatar sits above the text so a long name keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.md))
        HStack(alignment: .center, spacing: Constants.Spacing.sm) {
            layout {
                AvatarView(imageUrl: member.avatarUrl, name: member.membersDisplayName, size: 40)
                    .accessibilityHidden(true)
                details
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text(member.membersDisplayName)
                .font(.naarsHeadline)
                .foregroundColor(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            if !isRemovedList, let role = communityMemberRoleText(member.role) {
                NaarsChip(text: role)
            }
            Text(String(
                format: "community_member_joined".localized,
                member.joinedAt.formatted(date: .abbreviated, time: .omitted)
            ))
            .font(.naarsCaption)
            .foregroundColor(.secondary)
            if isRemovedList, let note = member.removalReason, !note.isEmpty {
                Text(String(format: "community_member_removal_note".localized, note))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Answers only `currentUserId` (nil); previews never sign in.
final class PreviewMembersAuthService: AuthServiceProtocol {
    var currentUserId: UUID? { nil }
    var currentProfile: Profile? { nil }
    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, name: String, car: String?) async throws {}
    func signOut() async throws {}
    func sendPasswordReset(email: String) async throws {}
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws {}
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult { .success }
}

@MainActor
enum CommunityMembersPreview {
    /// Ballard (owned) by default; `role` replaces the caller's role there.
    static func viewModel(
        role: CommunityRole = .owner,
        list: CommunityMembersList = .active,
        platformAdmin: Bool = false
    ) -> CommunityMembersViewModel {
        let service = PreviewCommunityService()
        let context = CommunityContext(
            service: service,
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { platformAdmin }
        )
        let ballard = PreviewCommunityService.sampleMemberships[1]
        let row = CommunityMembership(
            communityId: ballard.communityId, name: ballard.name, description: ballard.description,
            role: role, status: ballard.status, isPrimary: ballard.isPrimary, joinPolicy: ballard.joinPolicy,
            isPublic: ballard.isPublic, isDefault: ballard.isDefault, membersCanInvite: ballard.membersCanInvite,
            timezone: ballard.timezone, canInvite: ballard.canInvite, memberCount: ballard.memberCount,
            pendingCount: ballard.pendingCount, notificationsMuted: ballard.notificationsMuted,
            mutedUntil: ballard.mutedUntil, joinedAt: ballard.joinedAt, activatedAt: ballard.activatedAt
        )
        context.debugSetMemberships([PreviewCommunityService.sampleMemberships[0], row])
        let vm = CommunityMembersViewModel(
            communityId: row.communityId,
            communityName: row.name,
            adminService: service,
            communityContext: context,
            authService: PreviewMembersAuthService(),
            refreshDashboard: { _ in }
        )
        vm.list = list
        return vm
    }

    static var target: CommunityMembersTarget {
        let ballard = PreviewCommunityService.sampleMemberships[1]
        return CommunityMembersTarget(communityId: ballard.communityId, communityName: ballard.name)
    }
}

#Preview("Members, owner") {
    NavigationStack {
        CommunityMembersView(target: CommunityMembersPreview.target, viewModel: CommunityMembersPreview.viewModel())
    }
}

#Preview("Removed") {
    NavigationStack {
        CommunityMembersView(
            target: CommunityMembersPreview.target,
            viewModel: CommunityMembersPreview.viewModel(list: .removed)
        )
    }
}

#Preview("Not admin") {
    NavigationStack {
        CommunityMembersView(
            target: CommunityMembersPreview.target,
            viewModel: CommunityMembersPreview.viewModel(role: .member)
        )
    }
}

#Preview("Transfer banner") {
    NavigationStack {
        CommunityMembersView(
            target: CommunityMembersTarget(
                communityId: CommunityMembersPreview.target.communityId,
                communityName: CommunityMembersPreview.target.communityName,
                highlightTransfer: true
            ),
            viewModel: CommunityMembersPreview.viewModel()
        )
    }
}
#endif
