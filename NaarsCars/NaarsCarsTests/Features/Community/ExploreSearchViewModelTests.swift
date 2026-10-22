//
//  ExploreSearchViewModelTests.swift
//  NaarsCarsTests
//
//  Explore search: by name and near a place, stale answers, cancellation, Use my location, debounce
//

import XCTest
@testable import NaarsCars

@MainActor
final class ExploreSearchViewModelTests: XCTestCase {
    private var service: StubCommunityService!
    private var geocoder: StubPlaceGeocoder!
    private var locator: StubLocator!

    override func setUp() async throws {
        try await super.setUp()
        service = StubCommunityService(result: .success([]))
        geocoder = StubPlaceGeocoder()
        locator = StubLocator()
    }

    override func tearDown() async throws {
        service = nil
        geocoder = nil
        locator = nil
        try await super.tearDown()
    }

    private func makeViewModel(debounce: Duration = .zero) -> ExploreSearchViewModel {
        ExploreSearchViewModel(service: service, geocoder: geocoder, locator: locator, debounce: debounce)
    }

    private func result(_ name: String) -> CommunitySearchResult {
        CommunityFixtures.searchResult(UUID(), name: name)
    }

    private struct ProbeError: Error {}

    func testShortQuery_IsIdleAndCallsNothing() async {
        let vm = makeViewModel()

        await vm.search("a")

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.showsResults)
        XCTAssertTrue(service.searchCommunitiesCalls.isEmpty)
        XCTAssertTrue(service.findCommunitiesNearCalls.isEmpty)
        XCTAssertTrue(geocoder.forwardCalls.isEmpty)
    }

    func testTownQuery_RunsBothGroupsAndDropsNameDuplicatesFromNear() async {
        let a = result("Seattle Riders")
        let b = result("Ballard Neighbors")
        service.searchCommunitiesResult = .success([a])
        service.findCommunitiesNearResult = .success([a, b])
        geocoder.forwardResults["Seattle"] = GeocodedPlace(
            label: "Seattle", point: GeoPoint(latitude: 47.60621, longitude: -122.33207)
        )
        let vm = makeViewModel()

        await vm.search("Seattle")

        XCTAssertEqual(vm.phase, .results)
        XCTAssertTrue(vm.showsResults)
        XCTAssertEqual(vm.results.byName, [a])
        XCTAssertEqual(vm.results.near, [b])
        XCTAssertEqual(vm.results.placeLabel, "Seattle")
        XCTAssertEqual(service.findCommunitiesNearCalls, [GeoPoint(latitude: 47.606, longitude: -122.332)])
    }

    func testStreetAddress_SearchesNamesOnly() async {
        let vm = makeViewModel()

        await vm.search("5412 Probe Ln NW")

        XCTAssertTrue(geocoder.forwardCalls.isEmpty)
        XCTAssertTrue(service.findCommunitiesNearCalls.isEmpty)
        XCTAssertEqual(service.searchCommunitiesCalls, ["5412 Probe Ln NW"])
        XCTAssertEqual(vm.phase, .results)
        XCTAssertNil(vm.results.placeLabel)
    }

    func testStaleResponse_DoesNotOverwriteANewerQuery() async {
        let harbor = result("Harbor")
        let fremont = result("Fremont")
        service.searchCommunitiesHandler = { name in
            if name == "Harbor" {
                try await Task.sleep(for: .milliseconds(200))
                return [harbor]
            }
            return [fremont]
        }
        let vm = makeViewModel()

        let first = Task { await vm.search("Harbor") }
        for _ in 0..<200 where service.searchCommunitiesCalls.count < 1 { await Task.yield() }
        XCTAssertEqual(service.searchCommunitiesCalls, ["Harbor"])
        await vm.search("Fremont")
        await first.value

        XCTAssertEqual(vm.results.byName.map(\.name), ["Fremont"])
        XCTAssertEqual(vm.phase, .results)
    }

    func testOneGroupFailing_ShowsTheOtherBothFailingIsFailed() async {
        let near = result("Ballard Neighbors")
        geocoder.forwardResults["Ballard"] = GeocodedPlace(
            label: "Ballard, Seattle", point: GeoPoint(latitude: 47.668, longitude: -122.384)
        )
        service.searchCommunitiesResult = .failure(ProbeError())
        service.findCommunitiesNearResult = .success([near])
        let vm = makeViewModel()

        await vm.search("Ballard")
        XCTAssertEqual(vm.phase, .results)
        XCTAssertEqual(vm.results.byName, [])
        XCTAssertEqual(vm.results.near, [near])

        service.findCommunitiesNearResult = .failure(ProbeError())
        await vm.search("Ballard")
        XCTAssertEqual(vm.phase, .failed)

        let named = result("Ballard Riders")
        service.searchCommunitiesResult = .success([named])
        await vm.search("Ballard")
        XCTAssertEqual(vm.phase, .results)
        XCTAssertEqual(vm.results.byName, [named])
        XCTAssertEqual(vm.results.near, [])

        // A names-only query whose name search fails has nothing to show.
        service.searchCommunitiesResult = .failure(ProbeError())
        await vm.search("Ha")
        XCTAssertEqual(vm.phase, .failed)
    }

    func testCancelledSearch_IsNotAFailure() async {
        service.searchCommunitiesHandler = { _ in throw CancellationError() }
        let vm = makeViewModel()

        await vm.search("Ha")
        XCTAssertEqual(vm.phase, .searching)

        service.searchCommunitiesHandler = { _ in throw URLError(.cancelled) }
        await vm.search("Ha")
        XCTAssertEqual(vm.phase, .searching)

        let found = result("Harbor")
        service.searchCommunitiesHandler = nil
        service.searchCommunitiesResult = .success([found])
        await vm.search("Ha")
        XCTAssertEqual(vm.phase, .results)
        XCTAssertEqual(vm.results.byName, [found])
    }

    func testUseMyLocation_DeniedMakesNoCallAndNoNotice() async {
        locator.access = .denied
        locator.location = GeoPoint(latitude: 47.60621, longitude: -122.33207)
        let vm = makeViewModel()

        await vm.useMyLocation()

        XCTAssertEqual(locator.currentLocationCalls, 0)
        XCTAssertTrue(geocoder.reverseCalls.isEmpty)
        XCTAssertTrue(service.searchCommunitiesCalls.isEmpty)
        XCTAssertTrue(service.findCommunitiesNearCalls.isEmpty)
        XCTAssertNil(vm.locationNotice)
        XCTAssertFalse(vm.isLocating)
        XCTAssertFalse(vm.showsResults)
    }

    func testUseMyLocation_FillsTheFieldAndSearchesTheRoundedDeviceCoordinate() async {
        let rounded = GeoPoint(latitude: 47.606, longitude: -122.332)
        locator.location = GeoPoint(latitude: 47.60621, longitude: -122.33207)
        geocoder.reverseResult = GeocodedPlace(label: "Seattle", point: rounded)
        let vm = makeViewModel()

        await vm.useMyLocation()

        XCTAssertEqual(vm.query, "Seattle")
        XCTAssertTrue(vm.showsResults)
        XCTAssertFalse(vm.isLocating)
        XCTAssertEqual(vm.phase, .results)
        XCTAssertTrue(geocoder.forwardCalls.isEmpty)
        XCTAssertEqual(geocoder.reverseCalls, [rounded])
        XCTAssertEqual(service.searchCommunitiesCalls, ["Seattle"])
        XCTAssertEqual(service.findCommunitiesNearCalls, [rounded])
        XCTAssertEqual(vm.results.nearTitle, "Near Seattle")

        geocoder.reverseResult = nil
        await vm.useMyLocation()

        XCTAssertEqual(vm.query, "Seattle")
        XCTAssertEqual(vm.results.nearTitle, "Near you")
        XCTAssertEqual(service.searchCommunitiesCalls, ["Seattle"])
        XCTAssertEqual(service.findCommunitiesNearCalls, [rounded, rounded])

        vm.clear()
        XCTAssertFalse(vm.showsResults)
        XCTAssertEqual(vm.query, "")
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.results.isEmpty)
    }

    func testClear_AfterALocationSearchWithNoTownHidesTheResults() async {
        locator.location = GeoPoint(latitude: 47.60621, longitude: -122.33207)
        geocoder.reverseResult = nil
        let vm = makeViewModel()

        await vm.useMyLocation()

        XCTAssertEqual(vm.query, "")
        XCTAssertTrue(vm.showsResults)

        // ExploreView calls clear() when the field is dismissed with an empty query (ruling I2).
        vm.clear()

        XCTAssertFalse(vm.showsResults)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.results.isEmpty)
    }

    func testUseMyLocation_NoFixShowsTheUnavailableNotice() async {
        locator.access = .allowed
        locator.location = nil
        let vm = makeViewModel()

        await vm.useMyLocation()

        XCTAssertEqual(locator.currentLocationCalls, 1)
        XCTAssertEqual(vm.locationNotice, "Couldn't find where you are. Type a town or ZIP code instead.")
        XCTAssertFalse(vm.isLocating)
        XCTAssertTrue(geocoder.reverseCalls.isEmpty)
        XCTAssertTrue(service.findCommunitiesNearCalls.isEmpty)
        XCTAssertTrue(service.searchCommunitiesCalls.isEmpty)
    }

    func testUseMyLocation_NoFixLeavesATypedSearchToFinish() async throws {
        locator.location = nil
        let found = result("Seattle Riders")
        service.searchCommunitiesResult = .success([found])

        // A search still in its debounce runs once the location attempt gives up.
        let vm = makeViewModel(debounce: .milliseconds(50))
        vm.query = "Seattle"
        await vm.useMyLocation()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(service.searchCommunitiesCalls, ["Seattle"])
        XCTAssertEqual(vm.phase, .results)
        XCTAssertEqual(vm.results.byName, [found])
        XCTAssertTrue(vm.showsResults)

        // A search already running finishes and writes its answer; no spinner is left behind.
        service.searchCommunitiesHandler = { _ in
            try await Task.sleep(for: .milliseconds(100))
            return [found]
        }
        let running = makeViewModel()
        running.query = "Fremont"
        for _ in 0..<200 where service.searchCommunitiesCalls.count < 2 { await Task.yield() }
        XCTAssertEqual(service.searchCommunitiesCalls, ["Seattle", "Fremont"])
        await running.useMyLocation()
        for _ in 0..<100 where running.phase != .results { try await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(running.phase, .results)
        XCTAssertEqual(running.results.byName, [found])
        XCTAssertEqual(running.query, "Fremont")
    }

    func testQueryEdits_AreDebouncedIntoOneSearch() async throws {
        let vm = makeViewModel(debounce: .milliseconds(50))

        vm.query = "Ha"
        vm.query = "Har"
        vm.query = "Harb"
        XCTAssertTrue(vm.showsResults)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(service.searchCommunitiesCalls, ["Harb"])
    }

    // MARK: - Results view copy (test locale en)

    func testSearchRowDetail_JoinsAreaDistanceAndMembers() {
        func row(area: String?, distance: Double?, members: Int) -> CommunitySearchResult {
            CommunitySearchResult(
                id: UUID(), name: "Harbor Helpers", description: nil, joinPolicy: CommunityJoinPolicy.approve.rawValue,
                areaName: area, radiusMiles: area == nil ? nil : 2, memberCount: members, distanceMiles: distance
            )
        }
        XCTAssertEqual(CommunitySearchRow.detailText(for: row(area: "Harbor", distance: 0.4, members: 214)), "Harbor · 0.4 mi · 214 members")
        XCTAssertEqual(CommunitySearchRow.detailText(for: row(area: "Harbor", distance: nil, members: 214)), "Harbor · 214 members")
        XCTAssertEqual(CommunitySearchRow.detailText(for: row(area: nil, distance: nil, members: 214)), "214 members")
        XCTAssertEqual(CommunitySearchRow.detailText(for: row(area: nil, distance: nil, members: 1)), "1 member")
    }

    func testEmptyResultsText_GuestAndMember() {
        XCTAssertEqual(CommunitySearchResultsView.emptyText(isGuest: true), "No community here yet. Sign up to start one.")
        XCTAssertEqual(CommunitySearchResultsView.emptyText(isGuest: false), "No community here yet. Start one for your neighbors.")
    }
}
