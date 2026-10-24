//
//  PlaceQueryTests.swift
//  NaarsCars
//
//  The rules that decide whether typed text is a town or ZIP code, whether an address or a
//  geocoded item is street-level, and how a place is labelled (Release 2 discovery, Task 2)
//

import XCTest
@testable import NaarsCars

final class PlaceQueryTests: XCTestCase {

    func testIsZIP() {
        XCTAssertTrue(PlaceQuery.isZIP("98107")); XCTAssertTrue(PlaceQuery.isZIP(" 98107-1234 "))
        XCTAssertFalse(PlaceQuery.isZIP("9810")); XCTAssertFalse(PlaceQuery.isZIP("98107 Seattle"))
    }

    func testHasHouseNumber() {
        XCTAssertTrue(PlaceQuery.hasHouseNumber("5412 Probe Ln NW")); XCTAssertTrue(PlaceQuery.hasHouseNumber("Seattle, 12 Main St"))
        XCTAssertFalse(PlaceQuery.hasHouseNumber("Ballard")); XCTAssertFalse(PlaceQuery.hasHouseNumber("98107")); XCTAssertFalse(PlaceQuery.hasHouseNumber("Pier 66"))
    }

    func testIsStreetLevel() {
        XCTAssertTrue(PlaceQuery.isStreetLevel(fullAddress: "5412 Probe Ln NW, Seattle, WA"))
        XCTAssertFalse(PlaceQuery.isStreetLevel(fullAddress: "Seattle, WA")); XCTAssertFalse(PlaceQuery.isStreetLevel(fullAddress: "Ballard, Seattle, WA"))
        XCTAssertFalse(PlaceQuery.isStreetLevel(fullAddress: nil))
    }

    func testLooksLikeTownOrZIP() {
        for text in ["Ballard", "98107", "Capitol Hill"] { XCTAssertTrue(PlaceQuery.looksLikeTownOrZIP(text), text) }
        for text in ["Se", "5412 Probe Ln NW", "%%%", "   "] { XCTAssertFalse(PlaceQuery.looksLikeTownOrZIP(text), text) }
    }

    func testLabel_ZIPTownAndNeighborhood() {
        XCTAssertEqual(PlaceQuery.label(placeName: "Ballard", cityName: "Seattle", query: "ballard"), "Ballard, Seattle")
        XCTAssertEqual(PlaceQuery.label(placeName: "Seattle", cityName: "Seattle", query: "seattle"), "Seattle")
        XCTAssertEqual(PlaceQuery.label(placeName: nil, cityName: "Seattle", query: "98107"), "98107 · Seattle")
        XCTAssertNil(PlaceQuery.label(placeName: nil, cityName: nil, query: "Harbor"))
        XCTAssertEqual(PlaceQuery.label(placeName: String(repeating: "a", count: 90), cityName: nil, query: "a")?.count, 80)
        // The ZIP label passes the server's house-number pattern (the middle dot is not a letter).
        XCTAssertFalse(PlaceQuery.hasHouseNumber("98107 · Seattle"))
    }
}
