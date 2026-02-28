//
//  RideDirectionsLauncherTests.swift
//  NaarsCarsTests
//
//  Unit tests for RideDirectionsLauncher.buildMapItems (map item array from coords).
//

import XCTest
import CoreLocation
import MapKit
@testable import NaarsCars

final class RideDirectionsLauncherTests: XCTestCase {

    private let pickupCoord = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    private let dropoffCoord = CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3493)
    private let currentCoord = CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34)

    func testBuildMapItems_WithCurrentLocation_ReturnsThreeItems() {
        let items = RideDirectionsLauncher.buildMapItems(
            pickupCoord: pickupCoord,
            dropoffCoord: dropoffCoord,
            currentCoord: currentCoord,
            pickupName: "Pickup",
            dropoffName: "Dropoff"
        )
        XCTAssertEqual(items.count, 3, "Should be current, pickup, dropoff")
        XCTAssertEqual(items[0].name, "Current Location")
        XCTAssertEqual(items[1].name, "Pickup")
        XCTAssertEqual(items[2].name, "Dropoff")
    }

    func testBuildMapItems_WithoutCurrentLocation_ReturnsTwoItems() {
        let items = RideDirectionsLauncher.buildMapItems(
            pickupCoord: pickupCoord,
            dropoffCoord: dropoffCoord,
            currentCoord: nil,
            pickupName: "Pickup",
            dropoffName: "Dropoff"
        )
        XCTAssertEqual(items.count, 2, "Should be pickup, dropoff")
        XCTAssertEqual(items[0].name, "Pickup")
        XCTAssertEqual(items[1].name, "Dropoff")
    }

    func testBuildMapItems_MissingPickup_ReturnsEmpty() {
        let items = RideDirectionsLauncher.buildMapItems(
            pickupCoord: nil,
            dropoffCoord: dropoffCoord,
            currentCoord: currentCoord,
            pickupName: "Pickup",
            dropoffName: "Dropoff"
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testBuildMapItems_MissingDropoff_ReturnsEmpty() {
        let items = RideDirectionsLauncher.buildMapItems(
            pickupCoord: pickupCoord,
            dropoffCoord: nil,
            currentCoord: currentCoord,
            pickupName: "Pickup",
            dropoffName: "Dropoff"
        )
        XCTAssertTrue(items.isEmpty)
    }
}
