//
//  CommunityOnboardingView.swift
//  NaarsCars
//
//  The root of `.needsApplication`: join a community with a code, ask to join a public one,
//  or start your own
//

import SwiftUI

/// Shown to a signed-in account that belongs to no community yet. Joining or creating relaunches
/// the account check, which routes to the app (active) or the waiting screen (pending).
struct CommunityOnboardingView: View {
    @StateObject private var viewModel: CommunityOnboardingViewModel
    // Sign-out and delete-account actions, shared with the pending-review and restricted screens
    @StateObject private var accountViewModel = BannedAccountViewModel()
    @State private var showCreate = false
    /// Recorded by Create; acted on once the sheet (and its invite step) is gone.
    @State private var createdCommunityId: UUID?
    @State private var publicListFailed = false
    @State private var showDeleteConfirmation = false
    /// "<name> was archived." when this screen follows the archive of the account's last community.
    @State private var rootNoticeMessage: String?
    @FocusState private var nameFocused: Bool

    private let service: any CommunityServiceProtocol

    @MainActor init(
        viewModel: @autoclosure @escaping @MainActor () -> CommunityOnboardingViewModel = CommunityOnboardingViewModel(),
        service: any CommunityServiceProtocol = CommunityService.shared
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                header

                if viewModel.needsName {
                    nameStep
                }

                CommunityJoinOptionsView(
                    isEnabled: viewModel.optionsEnabled,
                    prefilledCode: viewModel.prefilledCode,
                    service: service,
                    onPublicListFailureChange: { publicListFailed = $0 },
                    onJoined: { viewModel.didJoin($0) }
                )

                if publicListFailed {
                    SecondaryButton(title: "onboarding_retry_check_account".localized) {
                        viewModel.retry()
                    }
                    .accessibilityLabel("onboarding_retry_check_account".localized)
                    .accessibilityHint("onboarding_retry_check_account_hint".localized)
                    .accessibilityIdentifier("onboarding.retry")
                }

                createCard

                accountActions
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.naarsBackground)
        .navigationTitle("onboarding_nav_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreate, onDismiss: createDismissed) {
            CreateCommunityView(
                service: service,
                viewModel: CreateCommunityViewModel(service: service),
                onCreated: { createdCommunityId = $0 }
            )
        }
        .accountDeletionFlow(
            isConfirming: $showDeleteConfirmation,
            viewModel: accountViewModel,
            message: "account_delete_pre_approval_message".localized
        )
        .task {
            // Taken first, so the confirmation shows while the name requirement loads.
            if let notice = viewModel.takeRootNotice() {
                rootNoticeMessage = notice
            }
            await viewModel.loadNameRequirement()
            // A code saved on Welcome before sign-in. The join options open it once they are
            // enabled (after the name step); only a redemption or a dead code clears the store.
            viewModel.prefilledCode = PendingInviteStore().peek()
        }
        // A join link opened while onboarding is on screen: the join options open the new code.
        .onReceive(NotificationCenter.default.publisher(for: PendingInviteStore.didChange)) { _ in
            viewModel.prefilledCode = PendingInviteStore().peek()
        }
        .toast(message: $rootNoticeMessage)
        .trackScreen("CommunityOnboarding")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: Constants.Spacing.md) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(.naarsPrimary)
                .accessibilityHidden(true)

            Text("onboarding_title".localized)
                .font(.naarsTitle2)
                .fontWeight(.semibold)
                .foregroundColor(.naarsTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("onboarding_body".localized)
                .font(.naarsBody)
                .foregroundColor(.naarsTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Constants.Spacing.md)
    }

    /// A repeat Sign in with Apple authorization creates "Apple User", which admins would review.
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text("application_name_label".localized)
                .font(.naarsHeadline)
                .foregroundColor(.naarsTextPrimary)

            TextField("application_name_placeholder".localized, text: $viewModel.name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .submitLabel(.continue)
                .onSubmit { saveName() }
                .accessibilityLabel("application_name_label".localized)
                .accessibilityIdentifier("onboarding.name")
                .onChange(of: viewModel.name) { _, _ in
                    if viewModel.nameError != nil { viewModel.nameError = nil }
                }

            if let nameError = viewModel.nameError {
                Text(nameError)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .accessibilityLabel("app_error_format".localized(with: nameError))
            }

            PrimaryButton(
                title: "onboarding_name_continue".localized,
                action: saveName,
                isLoading: viewModel.isSavingName,
                isDisabled: viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityLabel("onboarding_name_continue".localized)
            .accessibilityIdentifier("onboarding.name.continue")
        }
        .cardStyle()
    }

    private var createCard: some View {
        Button {
            nameFocused = false
            showCreate = true
        } label: {
            HStack(spacing: Constants.Spacing.md) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.naarsPrimary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text("onboarding_create_title".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.naarsTextPrimary)
                        .multilineTextAlignment(.leading)
                    Text("onboarding_create_body".localized)
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsTextSecondary)
                        .multilineTextAlignment(.leading)
                }
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
        .disabled(!viewModel.optionsEnabled)
        .padding(.top, Constants.Spacing.sm)
        .accessibilityLabel("onboarding_create_title".localized)
        .accessibilityHint("onboarding_create_body".localized)
        .accessibilityIdentifier("onboarding.create")
    }

    /// Always reachable: the account exists, and Settings is out of reach until a community
    /// accepts it (Guideline 5.1.1(v)).
    private var accountActions: some View {
        VStack(spacing: 0) {
            AccountTextAction(
                title: "application_sign_out".localized,
                isBusy: accountViewModel.isSigningOut
            ) {
                Task { await accountViewModel.signOut() }
            }
            .disabled(accountViewModel.isDeletingAccount)
            .accessibilityIdentifier("onboarding.signOut")

            AccountTextAction(
                title: "profile_delete_account".localized,
                isDestructive: true,
                isBusy: accountViewModel.isDeletingAccount
            ) {
                nameFocused = false
                showDeleteConfirmation = true
            }
            .disabled(accountViewModel.isSigningOut)
            .accessibilityIdentifier("onboarding.deleteAccount")
        }
        .padding(.top, Constants.Spacing.md)
        .padding(.bottom, Constants.Spacing.xl)
    }

    // MARK: - Actions

    private func saveName() {
        nameFocused = false
        Task { _ = await viewModel.saveName() }
    }

    /// The invite step shows inside the create sheet first (F1); the relaunch waits until it is gone.
    private func createDismissed() {
        guard let communityId = createdCommunityId else { return }
        createdCommunityId = nil
        viewModel.didCreate(communityId)
    }
}

#if DEBUG
#Preview("Name needed") {
    NavigationStack {
        CommunityOnboardingView(
            viewModel: CommunityOnboardingViewModel(
                loadStoredName: { "Apple User" },
                updateName: { _ in },
                relaunch: {}
            ),
            service: PreviewCommunityService()
        )
    }
}

#Preview("Name on file") {
    NavigationStack {
        CommunityOnboardingView(
            viewModel: CommunityOnboardingViewModel(
                loadStoredName: { "Sam" },
                updateName: { _ in },
                relaunch: {}
            ),
            service: PreviewCommunityService()
        )
    }
}

#Preview("Public list failed") {
    let service = PreviewCommunityService()
    service.failPublicCommunities = true
    return NavigationStack {
        CommunityOnboardingView(
            viewModel: CommunityOnboardingViewModel(
                loadStoredName: { "Sam" },
                updateName: { _ in },
                relaunch: {}
            ),
            service: service
        )
    }
}
#endif
