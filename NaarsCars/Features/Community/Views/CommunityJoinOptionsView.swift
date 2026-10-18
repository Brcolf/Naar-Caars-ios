//
//  CommunityJoinOptionsView.swift
//  NaarsCars
//
//  The two ways to join: type an invite code, or ask to join a public community.
//  Hosted inline by onboarding, and inside a sheet by My communities and the waiting screen.
//

import SwiftUI

struct CommunityJoinOptionsView: View {
    private struct ActiveSheet: Identifiable {
        let id = UUID()
        let target: JoinTarget
    }

    private struct AutoOpen: Equatable {
        let code: String?
        let enabled: Bool
    }

    @StateObject private var viewModel: CommunityJoinOptionsViewModel
    @State private var activeSheet: ActiveSheet?
    @State private var recordedResult: JoinResult?
    @State private var openedPrefilledCode: String?

    private let excludedCommunityIds: Set<UUID>
    private let isEnabled: Bool
    private let prefilledCode: String?
    private let service: any CommunityServiceProtocol
    private let onPublicListFailureChange: ((Bool) -> Void)?
    private let onJoined: (JoinResult) -> Void

    @MainActor init(
        excludedCommunityIds: Set<UUID> = [],
        isEnabled: Bool = true,
        prefilledCode: String? = nil,
        service: any CommunityServiceProtocol = CommunityService.shared,
        onPublicListFailureChange: ((Bool) -> Void)? = nil,
        onJoined: @escaping (JoinResult) -> Void
    ) {
        self.excludedCommunityIds = excludedCommunityIds
        self.isEnabled = isEnabled
        self.prefilledCode = prefilledCode
        self.service = service
        self.onPublicListFailureChange = onPublicListFailureChange
        self.onJoined = onJoined
        _viewModel = StateObject(wrappedValue: CommunityJoinOptionsViewModel(service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            Button {
                activeSheet = ActiveSheet(target: .code(prefilled: nil))
            } label: {
                HStack(spacing: Constants.Spacing.md) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.naarsPrimary)
                        .accessibilityHidden(true)
                    Text("community_join_enter_code".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.naarsTextPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.naarsCaption)
                        .foregroundColor(.naarsTextSecondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel("community_join_enter_code".localized)
            .accessibilityIdentifier("community.join.enterCode")

            Text("community_join_public_section".localized)
                .font(.naarsHeadline)
                .foregroundColor(.naarsTextPrimary)
                .padding(.top, Constants.Spacing.sm)
                .accessibilityAddTraits(.isHeader)

            publicList
        }
        .task(id: excludedCommunityIds) {
            await viewModel.load(excluding: excludedCommunityIds)
        }
        // Lets onboarding offer its own Try again (re-running the account check) when the list fails.
        .onChange(of: viewModel.errorMessage != nil) { _, failed in
            onPublicListFailureChange?(failed)
        }
        .onChange(of: AutoOpen(code: prefilledCode, enabled: isEnabled), initial: true) { _, new in
            guard let code = new.code, new.enabled, activeSheet == nil, code != openedPrefilledCode else { return }
            openedPrefilledCode = code
            activeSheet = ActiveSheet(target: .code(prefilled: code))
        }
        .sheet(item: $activeSheet, onDismiss: forwardRecordedResult) { sheet in
            JoinCommunitySheet(target: sheet.target, service: service) { result in
                recordedResult = result
            }
        }
    }

    // MARK: - Public list

    @ViewBuilder
    private var publicList: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Constants.Spacing.lg)
        } else if let message = viewModel.errorMessage {
            VStack(spacing: Constants.Spacing.sm) {
                Text(message)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
                    .multilineTextAlignment(.leading)
                SecondaryButton(title: "common_retry".localized) {
                    Task { await viewModel.load(excluding: excludedCommunityIds) }
                }
                .accessibilityIdentifier("community.join.retryPublic")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.publicCommunities.isEmpty {
            Text("community_join_public_empty".localized)
                .font(.naarsFootnote)
                .foregroundColor(.naarsTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(viewModel.publicCommunities) { community in
                Button {
                    activeSheet = ActiveSheet(target: .publicCommunity(community))
                } label: {
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                        Text(community.name)
                            .font(.naarsHeadline)
                            .foregroundColor(.naarsTextPrimary)
                            .multilineTextAlignment(.leading)
                        if let description = community.description, !description.isEmpty {
                            Text(description)
                                .font(.naarsFootnote)
                                .foregroundColor(.naarsTextSecondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(community.name)
                .accessibilityHint("community_join_public_hint".localized)
                .accessibilityIdentifier("community.join.public")
            }
        }
    }

    // MARK: - Result

    /// Done and a swipe both end up here: the host hears about a join once, after the sheet is gone.
    private func forwardRecordedResult() {
        guard let result = recordedResult else { return }
        recordedResult = nil
        onJoined(result)
    }
}

#if DEBUG
#Preview("Two public communities") {
    ScrollView {
        CommunityJoinOptionsView(service: PreviewCommunityService(), onJoined: { _ in })
            .padding(Constants.Spacing.md)
    }
    .background(Color.naarsBackground)
}

#Preview("None public") {
    let service = PreviewCommunityService()
    service.publicCommunities = []
    return ScrollView {
        CommunityJoinOptionsView(service: service, onJoined: { _ in })
            .padding(Constants.Spacing.md)
    }
    .background(Color.naarsBackground)
}

#Preview("Load failed") {
    let service = PreviewCommunityService()
    service.failPublicCommunities = true
    return ScrollView {
        CommunityJoinOptionsView(service: service, onJoined: { _ in })
            .padding(Constants.Spacing.md)
    }
    .background(Color.naarsBackground)
}

#Preview("Disabled") {
    ScrollView {
        CommunityJoinOptionsView(isEnabled: false, service: PreviewCommunityService(), onJoined: { _ in })
            .padding(Constants.Spacing.md)
    }
    .background(Color.naarsBackground)
}
#endif
