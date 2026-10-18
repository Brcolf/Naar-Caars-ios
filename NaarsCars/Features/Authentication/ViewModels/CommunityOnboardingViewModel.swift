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

    private let loadStoredName: @MainActor () async -> String?
    private let updateName: @MainActor (String) async throws -> Void
    private let relaunch: @MainActor () -> Void
    /// One relaunch per screen: a join, a create and Try again can all ask for one.
    private var didRelaunch = false

    /// - Parameters:
    ///   - loadStoredName: The profile's stored name; nil when it could not be read
    ///   - updateName: Saves a new name to the profile
    ///   - relaunch: Re-runs the launch account check
    init(
        loadStoredName: @escaping @MainActor () async -> String? = CommunityOnboardingViewModel.storedNameFromProfile,
        updateName: @escaping @MainActor (String) async throws -> Void = CommunityOnboardingViewModel.saveNameToProfile,
        relaunch: @escaping @MainActor () -> Void = {
            // Unstructured: this screen leaves the hierarchy at `.checkingAuth`.
            Task { @MainActor in await AppLaunchManager.shared.performCriticalLaunch() }
        }
    ) {
        self.loadStoredName = loadStoredName
        self.updateName = updateName
        self.relaunch = relaunch
    }

    // MARK: - Profile access

    /// The same read `ApplicationFieldsViewModel.loadNameRequirement` makes. Nil on any failure.
    static func storedNameFromProfile() async -> String? {
        guard let userId = await SignedInUser.resolveId(authService: AuthService.shared) else { return nil }
        if let profile = AuthService.shared.currentProfile, profile.id == userId {
            return profile.name
        }
        return try? await ProfileService.shared.fetchProfile(userId: userId).name
    }

    /// The name update `ApplicationFieldsViewModel.submitApplication` makes.
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

    /// Join and Create wait until the name requirement is known and, when needed, met.
    var optionsEnabled: Bool {
        hasLoadedNameRequirement && !needsName && !isSavingName
    }

    /// A blank or placeholder stored name needs replacing. A failed read leaves the name step
    /// off, as the application form did.
    func loadNameRequirement() async {
        let stored = await loadStoredName()
        if let stored {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            needsName = trimmed.isEmpty || trimmed == ApplicationFieldsViewModel.applePlaceholderName
        } else {
            needsName = false
        }
        hasLoadedNameRequirement = true
    }

    /// Validates and saves the typed name. True on success.
    func saveName() async -> Bool {
        guard !isSavingName else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = ApplicationFieldsViewModel.nameProblem(trimmed) {
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

    // MARK: - Results

    /// An active membership opens the app; a pending one opens the waiting screen.
    func didJoin(_ result: JoinResult) {
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
