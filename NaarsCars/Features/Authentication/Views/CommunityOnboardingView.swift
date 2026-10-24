//
//  CommunityOnboardingView.swift
//  NaarsCars
//
//  The root of `.needsApplication` (Get started): find a community by name or place, join the
//  one looked at as a guest, use an invite code, or start your own
//

import SwiftUI

/// Shown to a signed-in account that belongs to no community yet. Joining or creating relaunches
/// the account check, which routes to the app (active) or the waiting screen (pending).
struct CommunityOnboardingView: View {
    private struct JoinSheet: Identifiable {
        let id = UUID()
        let target: JoinTarget
    }

    /// The saved code and whether the options are open; the Join sheet opens the code once both hold.
    private struct AutoOpen: Equatable {
        let code: String?
        let enabled: Bool
    }

    @StateObject private var viewModel: CommunityOnboardingViewModel
    /// The search by name or place. Use my location is offered in Explore only (spec 3).
    @StateObject private var search: ExploreSearchViewModel
    // Sign-out and delete-account actions, shared with the pending-review and restricted screens
    @StateObject private var accountViewModel = BannedAccountViewModel()
    @State private var showCreate = false
    /// Recorded by Create; acted on once the sheet (and its invite step) is gone.
    @State private var createdCommunityId: UUID?
    @State private var joinSheet: JoinSheet?
    /// Recorded by the Join sheet; acted on once it is gone.
    @State private var recordedJoin: JoinResult?
    /// Recorded by a page opened from Create's nearby check; acted on once Create is gone.
    @State private var nearbyJoin: JoinResult?
    /// The saved code the Join sheet was last opened with, so it opens once.
    @State private var openedPrefilledCode: String?
    /// The community page opened from a search result.
    @State private var pageTarget: UUID?
    @State private var showDeleteConfirmation = false
    /// "<name> was archived." when this screen follows the archive of the account's last community.
    @State private var rootNoticeMessage: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let service: any CommunityServiceProtocol

    @MainActor init(
        viewModel: @autoclosure @escaping @MainActor () -> CommunityOnboardingViewModel = CommunityOnboardingViewModel(),
        service: any CommunityServiceProtocol = CommunityService.shared,
        search: @autoclosure @escaping @MainActor () -> ExploreSearchViewModel = ExploreSearchViewModel()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _search = StateObject(wrappedValue: search())
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                header

                if viewModel.needsName {
                    nameStep
                }

                if let viewed = viewModel.viewedCommunity {
                    viewedCard(viewed)
                }

                CommunitySearchPanel(
                    viewModel: search,
                    isGuest: false,
                    isEnabled: viewModel.optionsEnabled,
                    showsUseMyLocation: false,
                    membership: { _ in nil },
                    onSelect: { pageTarget = $0 }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onboarding.search")

                // An offline launch also lands here; a failed search is the sign of it. Otherwise the
                // same check stays reachable as a low-emphasis row under the account actions.
                if search.phase == .failed {
                    SecondaryButton(title: "onboarding_retry_check_account".localized) {
                        viewModel.retry()
                    }
                    .accessibilityLabel("onboarding_retry_check_account".localized)
                    .accessibilityHint("onboarding_retry_check_account_hint".localized)
                    .accessibilityIdentifier("onboarding.retry")
                }

                inviteCodeCard

                createCard

                accountActions
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.naarsBackground)
        .navigationTitle("onboarding_nav_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pageTarget) { communityId in
            // A join on the page goes to `didJoin` once its sheet is gone (one relaunch).
            CommunityPageView(communityId: communityId, onJoined: { viewModel.didJoin($0) })
                .id(communityId)
        }
        .sheet(item: $joinSheet, onDismiss: joinDismissed) { sheet in
            JoinCommunitySheet(target: sheet.target, service: service) { result in
                recordedJoin = result
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: createDismissed) {
            CreateCommunityView(
                service: service,
                viewModel: CreateCommunityViewModel(service: service),
                onCreated: { createdCommunityId = $0 },
                onJoinedFromNearby: { nearbyJoin = $0 }
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
            // A code saved on Welcome before sign-in. The Join sheet opens it once the options are
            // enabled (after the name step); only a redemption or a dead code clears the store.
            viewModel.prefilledCode = PendingInviteStore().peek()
        }
        // A join link opened while onboarding is on screen: the Join sheet opens the new code.
        .onReceive(NotificationCenter.default.publisher(for: PendingInviteStore.didChange)) { _ in
            viewModel.prefilledCode = PendingInviteStore().peek()
        }
        .onChange(of: AutoOpen(code: viewModel.prefilledCode, enabled: viewModel.optionsEnabled), initial: true) { _, new in
            guard let code = new.code, new.enabled, joinSheet == nil, !showCreate,
                  code != openedPrefilledCode else { return }
            openedPrefilledCode = code
            joinSheet = JoinSheet(target: .code(prefilled: code))
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

            Text("onboarding_find_title".localized)
                .font(.naarsTitle2)
                .fontWeight(.semibold)
                .foregroundColor(.naarsTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("onboarding_find_body".localized)
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

    /// The listed community this person looked at as a guest, with its join action.
    private func viewedCard(_ viewed: ViewedCommunity) -> some View {
        let policy = CommunityJoinPolicy(rawValue: viewed.joinPolicy)
        return VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            Text("onboarding_viewed_title".localized)
                .font(.naarsHeadline)
                .foregroundColor(.naarsTextPrimary)
                .accessibilityAddTraits(.isHeader)

            viewedLayout {
                CommunityMonogram(name: viewed.name)
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(viewed.name)
                        .font(.naarsHeadline)
                        .foregroundColor(.naarsTextPrimary)
                        .multilineTextAlignment(.leading)
                    if let policy {
                        CommunityPolicyChip(policy: policy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            PrimaryButton(
                title: String(format: "onboarding_viewed_join".localized, viewed.name),
                action: { joinViewed(viewed, policy: policy) },
                isDisabled: !viewModel.optionsEnabled
            )
            .accessibilityLabel(String(format: "onboarding_viewed_join".localized, viewed.name))
            .accessibilityIdentifier("onboarding.viewed.join")
        }
        .cardStyle()
    }

    /// Monogram beside the name; stacked at accessibility text sizes, where the name needs the width.
    private var viewedLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.md))
    }

    private var inviteCodeCard: some View {
        Button {
            nameFocused = false
            joinSheet = JoinSheet(target: .code(prefilled: viewModel.prefilledCode))
        } label: {
            HStack(spacing: Constants.Spacing.md) {
                Image(systemName: "key.fill")
                    .foregroundColor(.naarsPrimary)
                    .accessibilityHidden(true)
                Text("explore_have_invite_code".localized)
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
        .disabled(!viewModel.optionsEnabled)
        .accessibilityLabel("explore_have_invite_code".localized)
        .accessibilityIdentifier("onboarding.inviteCode")
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
            // An existing member whose launch check failed offline lands here too; the search may
            // succeed once back online, so the way back cannot depend on a failed search.
            if search.phase != .failed {
                AccountTextAction(title: "onboarding_retry_check_account".localized) {
                    nameFocused = false
                    viewModel.retry()
                }
                .disabled(accountViewModel.isSigningOut || accountViewModel.isDeletingAccount)
                .accessibilityLabel("onboarding_retry_check_account".localized)
                .accessibilityHint("onboarding_retry_check_account_hint".localized)
                .accessibilityIdentifier("onboarding.retry")
            }

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

    /// Ask to join for an approval (or open, or unknown) community; the invite code for an invite-only
    /// one, which a visitor cannot ask to join. The server decides either way.
    private func joinViewed(_ viewed: ViewedCommunity, policy: CommunityJoinPolicy?) {
        nameFocused = false
        if policy == .invite {
            joinSheet = JoinSheet(target: .code(prefilled: nil))
        } else {
            joinSheet = JoinSheet(target: .publicCommunity(PublicCommunity(
                id: viewed.id,
                name: viewed.name,
                description: nil,
                joinPolicy: viewed.joinPolicy,
                isDefault: false
            )))
        }
    }

    /// Done and a swipe both end up here: the relaunch waits until the Join sheet is gone.
    private func joinDismissed() {
        guard let result = recordedJoin else { return }
        recordedJoin = nil
        viewModel.didJoin(result)
    }

    /// The invite step shows inside the create sheet first (F1); the relaunch waits until it is gone.
    /// A join made on a page opened from the nearby check relaunches the same way.
    private func createDismissed() {
        if let communityId = createdCommunityId {
            createdCommunityId = nil
            nearbyJoin = nil
            viewModel.didCreate(communityId)
        } else if let result = nearbyJoin {
            nearbyJoin = nil
            viewModel.didJoin(result)
        }
    }
}

#if DEBUG
private enum OnboardingPreviewData {
    /// Get started with the preview service and stub geocoder. `viewed`: the community a guest looked
    /// at (nil: none). `query`: a search already typed.
    @MainActor
    static func screen(storedName: String, viewed: (name: String, policy: String)? = nil, query: String? = nil) -> some View {
        let service = PreviewCommunityService()
        let store = ViewedCommunityStore(defaults: UserDefaults(suiteName: "preview.onboarding")!)
        store.clear()
        if let viewed {
            store.save(id: UUID(), name: viewed.name, joinPolicy: viewed.policy)
        }
        let search = ExploreSearchViewModel(
            service: service,
            geocoder: PreviewPlaceGeocoder(),
            locator: PreviewLocator(),
            debounce: .zero
        )
        if let query { search.query = query }
        return NavigationStack {
            CommunityOnboardingView(
                viewModel: CommunityOnboardingViewModel(
                    loadStoredName: { storedName },
                    updateName: { _ in },
                    relaunch: {},
                    viewedStore: store
                ),
                service: service,
                search: search
            )
        }
        .environment(AppState())
    }
}

#Preview("Name needed") {
    OnboardingPreviewData.screen(storedName: "Apple User")
}

#Preview("Name on file") {
    OnboardingPreviewData.screen(storedName: "Sam")
}

#Preview("Looked at a community") {
    OnboardingPreviewData.screen(storedName: "Sam", viewed: (name: "Ballard Neighbors", policy: "approve"))
}

#Preview("Searching Ballard") {
    OnboardingPreviewData.screen(storedName: "Sam", query: "Ballard")
}
#endif
