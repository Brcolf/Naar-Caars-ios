//
//  CommunityOnboardingViewModelTests.swift
//  NaarsCarsTests
//
//  Onboarding, the root of `.needsApplication`: one relaunch per screen, the options stay closed
//  until the name requirement is known and met, and the name rules match the application form
//

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
}
