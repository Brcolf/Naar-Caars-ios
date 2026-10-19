//
//  JoinCommunitySheet.swift
//  NaarsCars
//
//  Join a community with a typed invite code, or ask to join a public one
//

import SwiftUI

struct JoinCommunitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: JoinCommunityViewModel
    @State private var showReport = false
    @State private var didAutoValidate = false

    @MainActor init(
        target: JoinTarget,
        service: any CommunityServiceProtocol = CommunityService.shared,
        onJoined: @escaping @MainActor (JoinResult) -> Void
    ) {
        // The view model reports the result the moment the server answers, so the presenter
        // records the join even when the sheet is swiped away from the done state.
        // Built here, not inside the StateObject autoclosure, which would have to capture the
        // non-Sendable callback. The initializer only stores its arguments.
        let model = JoinCommunityViewModel(target: target, service: service, onResult: onJoined)
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result = viewModel.result {
                    doneState(result)
                } else {
                    form
                }
            }
            .background(Color.naarsBackground)
            .navigationTitle(viewModel.communityName ?? "community_join_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common_cancel".localized) { dismiss() }
                            .disabled(viewModel.isWorking)
                            .accessibilityIdentifier("community.join.cancel")
                    }
                    if reportContext != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showReport = true
                            } label: {
                                Image(systemName: "flag")
                            }
                            .disabled(viewModel.isWorking)
                            .accessibilityLabel("community_report_this_community".localized)
                            .accessibilityIdentifier("community.join.report")
                        }
                    }
                }
            }
            .errorBanner(message: $viewModel.errorMessage)
            .interactiveDismissDisabled(viewModel.isWorking)
            .sheet(isPresented: $showReport) {
                if let context = reportContext {
                    ReportContentSheet(context: context)
                }
            }
            .task {
                // A prefilled code was typed or kept by the person already: check it once on open.
                guard !didAutoValidate, viewModel.isCodeTarget, !viewModel.normalizedCode.isEmpty else { return }
                didAutoValidate = true
                await viewModel.validate()
            }
        }
    }

    // MARK: - Report

    private var reportContext: ReportContext? {
        if let community = viewModel.publicCommunity {
            return .community(id: community.id, code: nil, name: community.name)
        }
        if viewModel.preview?.valid == true, let code = viewModel.checkedCode, let name = viewModel.communityName {
            return .community(id: nil, code: code, name: name)
        }
        return nil
    }

    // MARK: - Form

    private var form: some View {
        Form {
            if viewModel.isCodeTarget {
                codeSection
            }
            if let preview = viewModel.preview, preview.valid {
                previewSection(preview)
            }
            if canAnswer {
                answersSection
                Section {
                    PrimaryButton(
                        title: (viewModel.requiresApproval
                            ? "community_join_submit_request"
                            : "community_join_submit_join").localized,
                        action: { Task { await viewModel.submit() } },
                        isLoading: viewModel.isWorking,
                        isDisabled: !viewModel.canSubmit
                    )
                    .accessibilityIdentifier("community.join.submit")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if let name = viewModel.communityName {
                        Text(String(format: "community_join_disclosure".localized, name))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// The answer fields appear once there is something to join.
    private var canAnswer: Bool {
        if viewModel.publicCommunity != nil { return true }
        guard let preview = viewModel.preview else { return false }
        return preview.valid && preview.alreadyMember != true
    }

    private var codeSection: some View {
        Section {
            TextField("community_join_code_placeholder".localized, text: $viewModel.code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .submitLabel(.go)
                .onSubmit { Task { await viewModel.validate() } }
                .disabled(viewModel.isWorking)
                .accessibilityLabel("community_join_code_placeholder".localized)
                .accessibilityIdentifier("community.join.code")
            Button {
                Task { await viewModel.validate() }
            } label: {
                HStack {
                    Text("community_join_check_code".localized)
                    if viewModel.isWorking && viewModel.preview == nil {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isWorking || viewModel.normalizedCode.isEmpty)
            .accessibilityIdentifier("community.join.check")
        } header: {
            Text("community_join_enter_code".localized)
        }
    }

    private func previewSection(_ preview: InvitePreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                Text(preview.communityName ?? "")
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                Text((preview.requiresApproval ?? true
                    ? "community_join_requires_approval"
                    : "community_join_instant").localized)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
                if let count = preview.memberCount {
                    Text(memberCountLabel(count))
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var answersSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text("application_heard_about_label".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextPrimary)
                TextField(
                    "application_heard_about_placeholder".localized,
                    text: $viewModel.heardAbout,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .disabled(viewModel.isWorking)
                .accessibilityLabel("application_heard_about_label".localized)
                .accessibilityIdentifier("community.join.heardAbout")
                Text("\(viewModel.heardAbout.count)/\(Constants.Community.answerMaxLength)")
                    .font(.naarsCaption)
                    .foregroundColor(.naarsTextSecondary)
            }
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text("application_join_reason_label".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextPrimary)
                TextField(
                    "application_join_reason_placeholder".localized,
                    text: $viewModel.joinReason,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .disabled(viewModel.isWorking)
                .accessibilityLabel("application_join_reason_label".localized)
                .accessibilityIdentifier("community.join.reason")
                Text("\(viewModel.joinReason.count)/\(Constants.Community.answerMaxLength)")
                    .font(.naarsCaption)
                    .foregroundColor(.naarsTextSecondary)
            }
        } footer: {
            if !viewModel.requiresApproval {
                Text("community_join_answers_optional".localized)
            }
        }
    }

    // MARK: - Done

    private func doneState(_ result: JoinResult) -> some View {
        let name = viewModel.communityName ?? ""
        let isActive = result.status == .active
        return VStack(spacing: Constants.Spacing.lg) {
            Spacer()
            Image(systemName: isActive ? "checkmark.circle.fill" : "paperplane.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(isActive ? .naarsSuccess : .naarsPrimary)
                .accessibilityHidden(true)
            Text((isActive ? "community_join_done_active_title" : "community_join_done_pending_title").localized)
                .font(.naarsTitle2)
                .foregroundColor(.naarsTextPrimary)
                .multilineTextAlignment(.center)
            Text(String(
                format: (isActive ? "community_join_done_active_body" : "community_join_done_pending_body").localized,
                name
            ))
            .font(.naarsBody)
            .foregroundColor(.naarsTextSecondary)
            .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "common_done".localized) { dismiss() }
                .accessibilityIdentifier("community.join.done")
        }
        .padding(Constants.Spacing.lg)
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden(true)
    }

    private func memberCountLabel(_ count: Int) -> String {
        String(format: (count == 1 ? "community_member_count_one" : "community_member_count_other").localized, count)
    }
}

#if DEBUG
#Preview("Code, not checked") {
    JoinCommunitySheet(target: .code(prefilled: nil), service: PreviewCommunityService(), onJoined: { _ in })
}

#Preview("Code, checked") {
    JoinCommunitySheet(target: .code(prefilled: "NC7K2PQ9XA"), service: PreviewCommunityService(), onJoined: { _ in })
}

#Preview("Public community") {
    JoinCommunitySheet(
        target: .publicCommunity(PreviewCommunityService.samplePublicCommunities[0]),
        service: PreviewCommunityService(),
        onJoined: { _ in }
    )
}
#endif
