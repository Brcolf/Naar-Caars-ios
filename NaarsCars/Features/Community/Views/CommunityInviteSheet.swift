//
//  CommunityInviteSheet.swift
//  NaarsCars
//
//  Shows an invite code for a community with copy, share, QR and (for admins) options
//

import SwiftUI

/// The invite content without its own navigation container, so Create a community can push it
/// in its stack and the sheet can wrap it in one.
struct CommunityInviteContent: View {
    @StateObject private var viewModel: CommunityInviteViewModel
    @State private var toastMessage: String?
    let onDone: () -> Void

    init(
        communityId: UUID,
        communityName: String,
        isAdmin: Bool,
        service: any CommunityServiceProtocol = CommunityService.shared,
        onDone: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: CommunityInviteViewModel(
            communityId: communityId,
            communityName: communityName,
            isAdmin: isAdmin,
            service: service
        ))
        self.onDone = onDone
    }

    var body: some View {
        List {
            codeSection
            optionsSection
            if !viewModel.liveCodes.isEmpty {
                liveCodesSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
        .navigationTitle("community_invite_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common_done".localized, action: onDone)
                    .accessibilityIdentifier("community.invite.done")
            }
        }
        .errorBanner(message: $viewModel.errorMessage)
        .toast(message: $toastMessage)
        .task { await viewModel.prepare() }
    }

    // MARK: - Sections

    private var codeSection: some View {
        Section {
            VStack(spacing: Constants.Spacing.md) {
                if let code = viewModel.displayedCode {
                    Text(InviteCodeFormatter.formatCode(code))
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .foregroundColor(.naarsTextPrimary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("community_invite_code_label".localized)
                        .accessibilityValue(code.map(String.init).joined(separator: " "))
                        .accessibilityIdentifier("community.invite.code")

                    if let payload = viewModel.qrPayload,
                       let image = QRCodeRenderer.image(for: payload, dimension: 200) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .accessibilityLabel("community_invite_qr_accessibility".localized)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Constants.Spacing.md) {
                            inviteActionButtons(code: code)
                        }
                        VStack(spacing: Constants.Spacing.sm) {
                            inviteActionButtons(code: code, fillsWidth: true)
                        }
                    }
                } else if viewModel.isWorking || viewModel.errorMessage == nil {
                    ProgressView()
                        .padding(.vertical, Constants.Spacing.lg)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Constants.Spacing.sm)
        }
    }

    @ViewBuilder
    private func inviteActionButtons(code: String, fillsWidth: Bool = false) -> some View {
        Button {
            UIPasteboard.general.string = code
            HapticManager.success()
            toastMessage = "community_invite_copied".localized
        } label: {
            Label("community_invite_copy".localized, systemImage: "doc.on.doc")
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("community.invite.copy")

        if let message = viewModel.shareMessage {
            ShareLink(item: message) {
                Label("community_invite_share".localized, systemImage: "square.and.arrow.up")
                    .lineLimit(1)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("community.invite.share")
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section {
            if viewModel.isAdmin {
                Stepper(
                    viewModel.usesText(viewModel.maxUses),
                    value: $viewModel.maxUses,
                    in: 1...Constants.Community.adminInviteMaxUses
                )
                .accessibilityIdentifier("community.invite.uses")

                Picker("community_invite_expires_after".localized, selection: $viewModel.expiryDays) {
                    ForEach(Constants.Community.inviteExpiryDayChoices, id: \.self) { days in
                        Text(daysLabel(days)).tag(days)
                    }
                }
                .accessibilityIdentifier("community.invite.expiry")
            } else {
                Text("community_invite_member_rule".localized)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
            }

            SecondaryButton(title: "community_invite_new_code".localized) {
                Task { await viewModel.createCode() }
            }
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("community.invite.new")
        }
    }

    private var liveCodesSection: some View {
        Section("community_invite_live_codes".localized) {
            ForEach(viewModel.liveCodes) { row in
                HStack {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                        Text(InviteCodeFormatter.formatCode(row.code))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.naarsTextPrimary)
                        Text(detail(for: row))
                            .font(.naarsCaption)
                            .foregroundColor(.naarsTextSecondary)
                    }
                    Spacer()
                    Button("community_invite_revoke".localized, role: .destructive) {
                        Task { await viewModel.revoke(row) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isWorking)
                    .accessibilityLabel("community_invite_revoke".localized)
                    .accessibilityIdentifier("community.invite.revoke")
                }
            }
        }
    }

    // MARK: - Helpers

    private func daysLabel(_ days: Int) -> String {
        String(format: (days == 1 ? "community_invite_days_one" : "community_invite_days_other").localized, days)
    }

    private func detail(for row: CommunityInviteRow) -> String {
        var parts: [String] = []
        if let maxUses = row.maxUses {
            parts.append(String(format: "community_invite_used".localized, row.useCount, maxUses))
        }
        if let expiresAt = row.expiresAt {
            parts.append(String(
                format: "community_invite_expires_on".localized,
                expiresAt.formatted(date: .abbreviated, time: .omitted)
            ))
        }
        return parts.joined(separator: " · ")
    }
}

/// Invite sheet for a community the person belongs to.
struct CommunityInviteSheet: View {
    let communityId: UUID
    let communityName: String
    let isAdmin: Bool
    let service: any CommunityServiceProtocol
    let onDone: () -> Void

    init(
        communityId: UUID,
        communityName: String,
        isAdmin: Bool,
        service: any CommunityServiceProtocol = CommunityService.shared,
        onDone: @escaping () -> Void
    ) {
        self.communityId = communityId
        self.communityName = communityName
        self.isAdmin = isAdmin
        self.service = service
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            CommunityInviteContent(
                communityId: communityId,
                communityName: communityName,
                isAdmin: isAdmin,
                service: service,
                onDone: onDone
            )
        }
    }
}

#if DEBUG
#Preview("Member") {
    CommunityInviteSheet(
        communityId: UUID(),
        communityName: "Ballard Neighbors",
        isAdmin: false,
        service: PreviewCommunityService(),
        onDone: {}
    )
}

#Preview("Admin") {
    CommunityInviteSheet(
        communityId: UUID(),
        communityName: "Ballard Neighbors",
        isAdmin: true,
        service: PreviewCommunityService(),
        onDone: {}
    )
}
#endif
