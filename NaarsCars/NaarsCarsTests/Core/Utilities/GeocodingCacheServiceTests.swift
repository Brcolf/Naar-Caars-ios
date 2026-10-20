//
//  GeocodingCacheServiceTests.swift
//  NaarsCarsTests
//
//  Stubbed tests for the ride-cost place lookup: get_geocoding_multiplier / put_geocoding_multiplier
//  (20261019_0050), the request bodies, and the missing-function behaviour.
//

import XCTest
import CoreLocation
@testable import NaarsCars

final class GeocodingCacheServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RideCostEstimator.geocodingCacheAvailable = nil
        CommunityServiceURLProtocol.reset()
        URLProtocol.registerClass(CommunityServiceURLProtocol.self)
    }

    override func tearDown() {
        CommunityServiceURLProtocol.reset()
        URLProtocol.unregisterClass(CommunityServiceURLProtocol.self)
        RideCostEstimator.geocodingCacheAvailable = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func respond(status: Int = 200, with json: String) {
        CommunityServiceURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://localhost")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    private func onlyRequest(file: StaticString = #filePath, line: UInt = #line) throws -> CommunityServiceURLProtocol.Recorded {
        let all = CommunityServiceURLProtocol.recorded
        XCTAssertEqual(all.count, 1, "expected exactly one request", file: file, line: line)
        return try XCTUnwrap(all.first, file: file, line: line)
    }

    // MARK: - Lookup

    func testFetchCachedMultiplier_CallsLookupRPCWithTheKeyOnly() async throws {
        respond(with: "1.2")

        let value = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")

        XCTAssertEqual(value, 1.2)
        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/get_geocoding_multiplier")
        let body = try XCTUnwrap(request.body)
        XCTAssertEqual(Set(body.keys), ["p_location_key"])
        XCTAssertEqual(body["p_location_key"] as? String, "47.606_-122.332")
    }

    func testFetchCachedMultiplier_NullAnswerIsAMiss() async throws {
        respond(with: "null")

        let value = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")

        XCTAssertNil(value)
        _ = try onlyRequest()
    }

    func testFetchCachedMultiplier_NeverTouchesTheTable() async {
        respond(with: "null")

        _ = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")
        _ = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.607_-122.333")

        let paths = CommunityServiceURLProtocol.recorded.map(\.path)
        XCTAssertFalse(paths.isEmpty)
        XCTAssertFalse(paths.contains { $0.contains("/rest/v1/geocoding_cache") }, "recorded: \(paths)")
    }

    // MARK: - Write

    func testUpsert_SendsKeyCoordinatesAndMultiplierOnly() async throws {
        respond(with: "true")
        let coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

        await RideCostEstimator.upsertGeocodingCache(
            coordinate: coordinate,
            locationKey: "47.606_-122.332",
            multiplier: 1.1
        )

        let request = try onlyRequest()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/rest/v1/rpc/put_geocoding_multiplier")
        let body = try XCTUnwrap(request.body)
        XCTAssertEqual(Set(body.keys), ["p_location_key", "p_latitude", "p_longitude", "p_multiplier"])
        XCTAssertNil(body["placemark_data"])
        XCTAssertEqual(body["p_location_key"] as? String, "47.606_-122.332")
        XCTAssertEqual(try XCTUnwrap(body["p_latitude"] as? Double), 47.6062, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(body["p_longitude"] as? Double), -122.3321, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(body["p_multiplier"] as? Double), 1.1, accuracy: 0.000001)
    }

    // MARK: - Availability

    func testMissingFunction_DisablesLookupForTheSession() async {
        respond(
            status: 404,
            with: #"{"code":"PGRST202","details":"Searched for the function public.get_geocoding_multiplier","hint":null,"message":"Could not find the function public.get_geocoding_multiplier(p_location_key) in the schema cache"}"#
        )

        let first = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")
        XCTAssertNil(first)
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, 1)
        XCTAssertEqual(RideCostEstimator.geocodingCacheAvailable, false)

        let second = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")
        XCTAssertNil(second)
        XCTAssertEqual(CommunityServiceURLProtocol.recorded.count, 1, "no request once the function is known missing")
    }

    func testServerError_DoesNotDisableLookup() async {
        respond(
            status: 500,
            with: #"{"code":"XX000","details":null,"hint":null,"message":"internal error"}"#
        )

        let first = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")
        XCTAssertNil(first)
        let afterFirst = CommunityServiceURLProtocol.recorded.count
        XCTAssertGreaterThanOrEqual(afterFirst, 1)
        XCTAssertNotEqual(RideCostEstimator.geocodingCacheAvailable, false)

        _ = await RideCostEstimator.fetchCachedMultiplier(locationKey: "47.606_-122.332")
        XCTAssertGreaterThan(CommunityServiceURLProtocol.recorded.count, afterFirst, "a transient error leaves the lookup on")
    }
}
