//
//  FlightCodeParserTests.swift
//  NaarsCarsTests
//
//  Unit tests for FlightCodeParser (parseFirstFlightCode).
//

import XCTest
@testable import NaarsCars

final class FlightCodeParserTests: XCTestCase {

    func testDL123() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "DL123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL123")
        XCTAssertEqual(result?.airlineCode, "DL")
        XCTAssertEqual(result?.numberDigits, "123")
        XCTAssertTrue(result?.googleQueryURL.contains("DL123") == true)
        XCTAssertTrue(result?.googleQueryURL.contains("flight") == true)
    }

    func testDL_Space_123() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "DL 123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL123")
        XCTAssertEqual(result?.airlineCode, "DL")
    }

    func testDLHyphen123() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "DL-123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL123")
    }

    func testUA0123() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "UA 0123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "UA0123")
        XCTAssertEqual(result?.numberDigits, "0123")
    }

    func testAA100() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "AA100")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "AA100")
    }

    func testAS6() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "AS 6")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "AS6")
        XCTAssertEqual(result?.numberDigits, "6")
    }

    func testFlightLabelPrefix() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "Flight DL123")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL123")
    }

    func testFlightSuffix() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "DL123 at 6pm")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL123")
    }

    func testThreeLetterAirline() {
        // SWA is not in IATA DB (Southwest is WN); strong cue allows parsing
        let result = FlightCodeParser.parseFirstFlightCode(from: "flight SWA1234")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "SWA1234")
        XCTAssertEqual(result?.airlineCode, "SWA")
        XCTAssertEqual(result?.numberDigits, "1234")
    }

    func testNilAndEmptyReturnNil() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: nil))
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: ""))
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "   "))
    }

    func testNoFalsePositiveHashNumber() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "#1234"))
    }

    func testNoFalsePositiveOrderNumber() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "Order 1234")
        // "Or" could match 2 letters + "der" not digits; we need 2-3 letters then digits. "Order" gives Or then "der" - no digits after "Or". So no match for "Order 1234" as a single flight. Actually: "r " then "1234" - the 2 letters would need to be right before optional space and digits. So "r 1234" - "r " is one letter. So no match. Good.
        XCTAssertNil(result)
    }

    func testFirstMatchOnly() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "DL100 and UA 200")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL100")
    }

    // MARK: - Natural-language and false-positive cases

    func testAlaskaFlightAS587() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "Alaska flight AS587")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "AS587")
        XCTAssertEqual(result?.airlineCode, "AS")
        XCTAssertEqual(result?.numberDigits, "587")
    }

    func testOnAS587Tonight() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "on AS 587 tonight")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "AS587")
    }

    func testDL1234LandingTime() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "DL1234 landing 9:30")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "DL1234")
    }

    func testNoFalsePositiveStreetAddress() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "pickup at 1545 NW Market St"))
    }

    func testNoFalsePositiveTimeOnly() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "arrive 10:15"))
    }

    func testFlightColonUA12BaggageClaim() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "Flight: UA 12, baggage claim")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "UA12")
        XCTAssertEqual(result?.airlineCode, "UA")
        XCTAssertEqual(result?.numberDigits, "12")
    }

    func testFlightColonLowercaseUA12() {
        let result = FlightCodeParser.parseFirstFlightCode(from: "flight: ua 12")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.normalized, "UA12")
    }

    // MARK: - Regression: no false positives from roads / street abbreviations

    func testNoFalsePositiveSR99SeaTac() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "Take SR 99 to SeaTac"))
    }

    func testNoFalsePositiveNE45th() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "Meet at NE 45th"))
    }

    func testNoFalsePositiveWA520Bridge() {
        XCTAssertNil(FlightCodeParser.parseFirstFlightCode(from: "WA 520 bridge"))
    }
}
