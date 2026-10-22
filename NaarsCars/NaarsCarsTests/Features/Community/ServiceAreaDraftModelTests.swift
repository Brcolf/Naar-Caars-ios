//
//  ServiceAreaDraftModelTests.swift
//  NaarsCarsTests
//
//  The service-area draft: a street address is refused before any geocoding, a town resolves to
//  its label and centre, the nearby check runs again after the area changes, an overlap needs a
//  reason of 1-300 characters, and a failed check blocks submitting
//

import XCTest
@testable import NaarsCars

@MainActor
final class ServiceAreaDraftModelTests: XCTestCase {
    private let seattle = GeocodedPlace(label: "Seattle", point: GeoPoint(latitude: 47.606, longitude: -122.332))

    private func makeModel(
        geocoder: StubPlaceGeocoder = StubPlaceGeocoder(),
        service: StubCommunityService = StubCommunityService(result: .success([])),
        excluding communityId: UUID? = nil
    ) -> ServiceAreaDraftModel {
        ServiceAreaDraftModel(geocoder: geocoder, service: service, excluding: communityId)
    }

    /// A model whose query "Seattle" has resolved.
    private func resolvedModel(
        service: StubCommunityService = StubCommunityService(result: .success([])),
        excluding communityId: UUID? = nil
    ) async -> ServiceAreaDraftModel {
        let geocoder = StubPlaceGeocoder()
        geocoder.forwardResults = ["Seattle": seattle]
        let model = makeModel(geocoder: geocoder, service: service, excluding: communityId)
        model.placeQuery = "Seattle"
        await model.resolvePlace()
        return model
    }

    func testStreetAddress_IsRefusedWithoutGeocoding() async {
        let geocoder = StubPlaceGeocoder()
        let model = makeModel(geocoder: geocoder)
        model.placeQuery = "5412 Probe Ln NW"

        await model.resolvePlace()

        XCTAssertEqual(model.placeError, "community_area_street_refused".localized)
        XCTAssertTrue(geocoder.forwardCalls.isEmpty)
        XCTAssertNil(model.place)
        XCTAssertNil(model.area)
    }

    func testTown_ResolvesTheLabelAndCenter() async {
        let model = await resolvedModel()

        XCTAssertNil(model.placeError)
        XCTAssertEqual(model.place, seattle)
        XCTAssertEqual(model.radiusMiles, Constants.Community.defaultAreaRadiusMiles)
        XCTAssertEqual(model.area, ServiceArea(name: "Seattle", center: seattle.point, radiusMiles: 2))
        XCTAssertFalse(model.isResolving)
        // Resolving does not check the area: that is its own step.
        XCTAssertFalse(model.nearbyChecked)
        XCTAssertFalse(model.isReadyToSubmit)

        // Editing the query drops the resolved place.
        model.placeQuery = "Seattl"
        XCTAssertNil(model.place)
        XCTAssertNil(model.area)
    }

    func testNotFound_ShowsTheMessage() async {
        let geocoder = StubPlaceGeocoder()
        let model = makeModel(geocoder: geocoder)
        model.placeQuery = "Nowhereville"

        await model.resolvePlace()

        XCTAssertEqual(geocoder.forwardCalls, ["Nowhereville"])
        XCTAssertEqual(model.placeError, "community_area_not_found".localized)
        XCTAssertNil(model.area)
    }

    func testRadiusChange_RequiresANewNearbyCheck() async {
        let service = StubCommunityService(result: .success([]))
        let model = await resolvedModel(service: service)
        await model.checkNearby()
        XCTAssertTrue(model.nearbyChecked)
        XCTAssertTrue(model.isReadyToSubmit)

        model.radiusMiles = 5

        XCTAssertFalse(model.nearbyChecked)
        XCTAssertFalse(model.isReadyToSubmit)
        await model.checkNearby()
        XCTAssertTrue(model.isReadyToSubmit)
        XCTAssertEqual(service.checkCommunityAreaCalls.map(\.area.radiusMiles), [2, 5])
    }

    func testOverlaps_RequireAReason() async {
        let service = StubCommunityService(result: .success([]))
        service.checkCommunityAreaResult = .success([
            CommunityFixtures.searchResult(CommunityFixtures.communityA, name: "Community A", distance: 0.8)
        ])
        let model = await resolvedModel(service: service)
        await model.checkNearby()

        XCTAssertEqual(model.overlaps.map(\.id), [CommunityFixtures.communityA])
        XCTAssertTrue(model.needsReason)
        XCTAssertFalse(model.isReadyToSubmit)

        model.reason = "   "
        XCTAssertFalse(model.isReadyToSubmit)

        model.reason = "Parents of one school"
        XCTAssertTrue(model.isReadyToSubmit)

        model.reason = String(repeating: "a", count: Constants.Community.listingReasonMaxLength + 1)
        XCTAssertFalse(model.isReadyToSubmit)
    }

    func testNearbyCheck_SendsTheExcludedCommunity() async throws {
        let service = StubCommunityService(result: .success([]))
        let model = await resolvedModel(service: service, excluding: CommunityFixtures.communityA)

        await model.checkNearby()

        let call = try XCTUnwrap(service.checkCommunityAreaCalls.last)
        XCTAssertEqual(call.excluding, CommunityFixtures.communityA)
        XCTAssertEqual(call.area, ServiceArea(name: "Seattle", center: seattle.point, radiusMiles: 2))
    }

    func testNearbyCheckFailure_BlocksSubmit() async {
        let service = StubCommunityService(result: .success([]))
        service.checkCommunityAreaResult = .failure(URLError(.notConnectedToInternet))
        let model = await resolvedModel(service: service)

        await model.checkNearby()

        XCTAssertTrue(model.nearbyCheckFailed)
        XCTAssertFalse(model.nearbyChecked)
        XCTAssertFalse(model.isReadyToSubmit)

        // Retrying after the network is back clears the failure.
        service.checkCommunityAreaResult = .success([])
        await model.checkNearby()
        XCTAssertFalse(model.nearbyCheckFailed)
        XCTAssertTrue(model.isReadyToSubmit)
    }

    func testReset_SeedsTheStoredAreaAndClearsTheCheck() async {
        let service = StubCommunityService(result: .success([]))
        service.checkCommunityAreaResult = .success([
            CommunityFixtures.searchResult(CommunityFixtures.communityB, name: "Community B", distance: 1.2)
        ])
        let model = await resolvedModel(service: service)
        await model.checkNearby()
        model.reason = "Parents of one school"

        model.reset(to: CommunityFixtures.seattleArea)

        XCTAssertEqual(model.area, CommunityFixtures.seattleArea)
        XCTAssertEqual(model.placeQuery, "Seattle")
        XCTAssertEqual(model.radiusMiles, 10)
        XCTAssertFalse(model.nearbyChecked)
        XCTAssertTrue(model.overlaps.isEmpty)
        XCTAssertEqual(model.reason, "")

        model.reset(to: nil)
        XCTAssertNil(model.area)
        XCTAssertEqual(model.placeQuery, "")
        XCTAssertEqual(model.radiusMiles, Constants.Community.defaultAreaRadiusMiles)
    }
}
