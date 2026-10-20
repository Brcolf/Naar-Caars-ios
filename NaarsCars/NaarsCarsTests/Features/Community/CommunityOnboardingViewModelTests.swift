//
//  CommunityOnboardingViewModelTests.swift
//  NaarsCarsTests
//
//  Onboarding, the root of `.needsApplication`: one relaunch per screen, the options stay closed
//  until the name requirement is known and met, and the name rules match the sign-up form
//

import SwiftUI
import XCTest
@testable import NaarsCars

@MainActor
final class CommunityOnboardingViewModelTests: XCTestCase {
    private struct SaveFailure: Error {}

    private var relaunchCount = 0
    private var savedNames: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        relaunchCount = 0
        savedNames = []
    }

    private func makeViewModel(
        storedName: String?,
        updateFails: Bool = false
    ) -> CommunityOnboardingViewModel {
        CommunityOnboardingViewModel(
            loadStoredName: { storedName },
            updateName: { [weak self] name in
                self?.savedNames.append(name)
                if updateFails { throw SaveFailure() }
            },
            relaunch: { [weak self] in self?.relaunchCount += 1 }
        )
    }

    // MARK: - Relaunch

    func testDidJoin_RelaunchesExactlyOnce() {
        let viewModel = makeViewModel(storedName: "Sam")
        viewModel.didJoin(JoinResult(communityId: CommunityFixtures.communityA, status: .active))
        viewModel.didJoin(JoinResult(communityId: CommunityFixtures.communityB, status: .pending))
        XCTAssertEqual(relaunchCount, 1)
    }

    func testDidCreate_RelaunchesExactlyOnce() {
        let viewModel = makeViewModel(storedName: "Sam")
        viewModel.didCreate(CommunityFixtures.communityA)
        viewModel.didCreate(CommunityFixtures.communityA)
        viewModel.retry()
        XCTAssertEqual(relaunchCount, 1)
    }

    // MARK: - Name requirement

    func testOptions_GatedUntilNameRequirementLoaded() async {
        let viewModel = makeViewModel(storedName: "Sam")
        XCTAssertFalse(viewModel.optionsEnabled)

        await viewModel.loadNameRequirement()

        XCTAssertTrue(viewModel.hasLoadedNameRequirement)
        XCTAssertFalse(viewModel.needsName)
        XCTAssertTrue(viewModel.optionsEnabled)
    }

    func testLoadNameRequirement_FailedReadKeepsOptionsOpen() async {
        let viewModel = makeViewModel(storedName: nil)

        await viewModel.loadNameRequirement()

        XCTAssertFalse(viewModel.needsName)
        XCTAssertTrue(viewModel.optionsEnabled)
    }

    func testSaveName_RejectsApplePlaceholderAndBlank() async {
        let viewModel = makeViewModel(storedName: "Apple User")
        await viewModel.loadNameRequirement()
        XCTAssertTrue(viewModel.needsName)
        XCTAssertFalse(viewModel.optionsEnabled)

        viewModel.name = "Apple User"
        let placeholderSaved = await viewModel.saveName()
        XCTAssertFalse(placeholderSaved)
        XCTAssertEqual(viewModel.nameError, "signup_error_name_required".localized)

        viewModel.nameError = nil
        viewModel.name = "   "
        let blankSaved = await viewModel.saveName()
        XCTAssertFalse(blankSaved)
        XCTAssertEqual(viewModel.nameError, "signup_error_name_required".localized)

        XCTAssertEqual(savedNames, [])
        XCTAssertFalse(viewModel.optionsEnabled)
    }

    func testNameProblem_RejectsPlaceholderEmptyAndShortNames() {
        // Same rules and messages as the sign-up form's name field (moved from ApplicationFieldsViewModel).
        XCTAssertEqual(CommunityOnboardingViewModel.nameProblem(""), "signup_error_name_required".localized)
        XCTAssertEqual(CommunityOnboardingViewModel.nameProblem(CommunityOnboardingViewModel.applePlaceholderName),
                       "signup_error_name_required".localized)
        XCTAssertEqual(CommunityOnboardingViewModel.nameProblem("A"), "signup_error_name_too_short".localized)
        XCTAssertEqual(CommunityOnboardingViewModel.nameProblem(String(repeating: "a", count: 101)),
                       "signup_error_name_too_long".localized)
        XCTAssertNil(CommunityOnboardingViewModel.nameProblem("Sam Neighbor"))
        XCTAssertEqual(CommunityOnboardingViewModel.applePlaceholderName, "Apple User")   // AuthService+AppleSignIn.swift:378
    }

    func testSaveName_SuccessClearsNeedsNameAndOpensOptions() async {
        let viewModel = makeViewModel(storedName: "")
        await viewModel.loadNameRequirement()
        XCTAssertTrue(viewModel.needsName)

        viewModel.name = " Sam Lee "
        let saved = await viewModel.saveName()

        XCTAssertTrue(saved)
        XCTAssertEqual(savedNames, ["Sam Lee"])
        XCTAssertFalse(viewModel.needsName)
        XCTAssertNil(viewModel.nameError)
        XCTAssertTrue(viewModel.optionsEnabled)
    }

    func testSaveName_FailureKeepsNameStep() async {
        let viewModel = makeViewModel(storedName: "Apple User", updateFails: true)
        await viewModel.loadNameRequirement()

        viewModel.name = "Sam Lee"
        let saved = await viewModel.saveName()

        XCTAssertFalse(saved)
        XCTAssertTrue(viewModel.needsName)
        XCTAssertEqual(viewModel.nameError, "community_error_generic".localized)
        XCTAssertFalse(viewModel.optionsEnabled)
    }

    // MARK: - Root notice

    func testTakeRootNotice_ReturnsItOnceAndClearsIt() {
        RootNotice.pending = "Ballard Neighbors was archived."
        defer { RootNotice.pending = nil }
        let viewModel = makeViewModel(storedName: "Sam")

        XCTAssertEqual(viewModel.takeRootNotice(), "Ballard Neighbors was archived.")
        XCTAssertNil(RootNotice.pending)
        XCTAssertNil(viewModel.takeRootNotice())
        XCTAssertNil(makeViewModel(storedName: "Sam").takeRootNotice(), "a later root does not show it again")
    }

    /// Phase 4 gate D4: the notice taken in a launch root's first `.task` stays on screen. The
    /// toast's first task, started for nil, used to read it through the binding and, cancelled for
    /// the new message, clear it within a frame; onboarding never showed it on device. Hosted in a
    /// window because the race is between SwiftUI's own tasks; the switch is animated as in ContentView.
    func testRootNotice_TakenInTheRootsFirstTaskStaysOnScreen() async throws {
        let notice = "Ballard Neighbors was archived."
        RootNotice.pending = notice
        defer { RootNotice.pending = nil }
        let host = RootNoticeHost()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: RootNoticeHostView(host: host))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await Task.sleep(nanoseconds: 300_000_000)
        host.showsRoot = true
        // Well inside the toast's shortest display time (Constants.Timing.toastMinimumDuration).
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNil(RootNotice.pending, "the root took it")
        XCTAssertEqual(host.messages.first, notice)
        XCTAssertEqual(host.messages.last, notice, "still on screen; message changes: \(host.messages)")
    }
}

// MARK: - Root notice host (testRootNotice_TakenInTheRootsFirstTaskStaysOnScreen)

@MainActor @Observable
private final class RootNoticeHost {
    var showsRoot = false
    /// Every value the root's toast message took, in order.
    @ObservationIgnored var messages: [String?] = []
}

private struct RootNoticeHostView: View {
    let host: RootNoticeHost

    var body: some View {
        Group {
            if host.showsRoot {
                NavigationStack { RootNoticeProbe(host: host) }
            } else {
                TabView { Text(verbatim: "main").tabItem { Text(verbatim: "main") } }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: host.showsRoot)
    }
}

/// The notice code of `CommunityOnboardingView` and `PendingApprovalView`: taken in `.task`,
/// shown with `.toast(message:)`.
private struct RootNoticeProbe: View {
    let host: RootNoticeHost
    @State private var message: String?

    var body: some View {
        ScrollView { Text(verbatim: "root") }
            .task {
                if let notice = RootNotice.take() { message = notice }
            }
            .onChange(of: message) { _, new in host.messages.append(new) }
            .toast(message: $message)
    }
}
