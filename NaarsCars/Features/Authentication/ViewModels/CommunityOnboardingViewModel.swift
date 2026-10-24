//
//  CommunityOnboardingViewModel.swift
//  NaarsCars
//
//  The root of `.needsApplication`: a signed-in account with no community picks one
//

import Foundation
internal import Combine

/// Drives the onboarding screen. It asks for a name first when the profile has none (a repeat
/// Sign in with Apple authorization creates "Apple User"), keeps the join and create options
/// closed until that is settled, and relaunches once after a join or a create so the account
/// check routes the person to the app or the waiting screen.
@MainActor
final class CommunityOnboardingViewModel: ObservableObject {
    @Published private(set) var needsName = false
    @Published private(set) var hasLoadedNameRequirement = false
    @Published var name = ""
    @Published var nameError: String?
    @Published private(set) var isSavingName = false
    /// An invite code to open as soon as the options are enabled (filled from `PendingInviteStore`).
    @Published var prefilledCode: String?
    /// The listed community this person looked at as a guest ("You were looking at"); read once at
    /// init, nil after a join.
    @Published private(set) var viewedCommunity: ViewedCommunity?

    /// Apple sends the person's name only on the first authorization. A repeat authorization
    /// (for example after starting on the Sign In screen) creates the profile with this
    /// placeholder, which admins and later neighbours would otherwise see.
    static let applePlaceholderName = "Apple User"

    private let loadStoredName: @MainActor () async -> String?
    private let updateName: @MainActor (String) async throws -> Void
    private let relaunch: @MainActor () -> Void
    private let viewedStore: ViewedCommunityStore
    /// One relaunch per screen: a join, a create and Try again can all ask for one.
    private var didRelaunch = false

    /// - Parameters:
    ///   - loadStoredName: The profile's stored name; nil when it could not be read
    ///   - updateName: Saves a new name to the profile
    ///   - relaunch: Re-runs the launch account check
    ///   - viewedStore: The community a guest viewed before signing up
    init(
        loadStoredName: @escaping @MainActor () async -> String? = CommunityOnboardingViewModel.storedNameFromProfile,
        updateName: @escaping @MainActor (String) async throws -> Void = CommunityOnboardingViewModel.saveNameToProfile,
        relaunch: @escaping @MainActor () -> Void = {
            // Unstructured: this screen leaves the hierarchy at `.checkingAuth`.
            Task { @MainActor in await AppLaunchManager.shared.performCriticalLaunch() }
        },
        viewedStore: ViewedCommunityStore = ViewedCommunityStore()
    ) {
        self.loadStoredName = loadStoredName
        self.updateName = updateName
        self.relaunch = relaunch
        self.viewedStore = viewedStore
        // A local read (no publisher, no repository): shown with the screen's first frame.
        self.viewedCommunity = viewedStore.peek()
    }

    // MARK: - Profile access

    /// The read the name step makes. Nil on any failure.
    static func storedNameFromProfile() async -> String? {
        guard let userId = await SignedInUser.resolveId(authService: AuthService.shared) else { return nil }
        if let profile = AuthService.shared.currentProfile, profile.id == userId {
            return profile.name
        }
        return try? await ProfileService.shared.fetchProfile(userId: userId).name
    }

    /// The name update the name step makes.
    static func saveNameToProfile(_ name: String) async throws {
        guard let userId = await SignedInUser.resolveId(authService: AuthService.shared) else {
            throw AppError.unauthorized
        }
        try await ProfileService.shared.updateProfile(
            userId: userId,
            name: name,
            phoneNumber: nil,
            car: nil,
            avatarUrl: nil,
            shouldUpdateAvatar: false
        )
    }

    // MARK: - Name

    /// Same rules and messages as the name field on the sign-up form. Nil when the name is fine.
    static func nameProblem(_ trimmedName: String) -> String? {
        if trimmedName.isEmpty || trimmedName == applePlaceholderName {
            return "signup_error_name_required".localized
        }
        if trimmedName.count < 2 {
            return "signup_error_name_too_short".localized
        }
        if trimmedName.count > 100 {
            return "signup_error_name_too_long".localized
        }
        if !Validators.isSafeUserInput(trimmedName) {
            return "signup_error_name_invalid_characters".localized
        }
        return nil
    }

    /// Join and Create wait until the name requirement is known and, when needed, met.
    var optionsEnabled: Bool {
        hasLoadedNameRequirement && !needsName && !isSavingName
    }

    /// A blank or placeholder stored name needs replacing. A failed read leaves the name step
    /// off.
    func loadNameRequirement() async {
        let stored = await loadStoredName()
        if let stored {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            needsName = trimmed.isEmpty || trimmed == Self.applePlaceholderName
        } else {
            needsName = false
        }
        hasLoadedNameRequirement = true
    }

    /// Validates and saves the typed name. True on success.
    func saveName() async -> Bool {
        guard !isSavingName else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.nameProblem(trimmed) {
            nameError = problem
            return false
        }
        let sanitized = Validators.sanitizeUserInput(trimmed, maxLength: 100)

        isSavingName = true
        defer { isSavingName = false }
        nameError = nil
        do {
            try await updateName(sanitized)
            needsName = false
            nameError = nil
            return true
        } catch {
            AppLogger.error("auth", "Failed to save onboarding name: \(error.localizedDescription)")
            nameError = "community_error_generic".localized
            return false
        }
    }

    // MARK: - Root notice

    /// The confirmation left by an archive of the account's last community (`RootNotice`), once;
    /// nil afterwards, so it never shows again on this or a later root.
    func takeRootNotice() -> String? {
        RootNotice.take()
    }

    // MARK: - Results

    /// An active membership opens the app; a pending one opens the waiting screen. The viewed
    /// community has served its purpose (joined, or the person chose another one).
    func didJoin(_ result: JoinResult) {
        viewedStore.clear()
        viewedCommunity = nil
        relaunchOnce()
    }

    /// Called from the create sheet's `onDismiss`, after the invite sheet has been shown.
    func didCreate(_ communityId: UUID) {
        relaunchOnce()
    }

    /// Re-runs the account check (an offline launch also lands on this screen).
    func retry() {
        relaunchOnce()
    }

    private func relaunchOnce() {
        guard !didRelaunch else { return }
        didRelaunch = true
        relaunch()
    }
}
