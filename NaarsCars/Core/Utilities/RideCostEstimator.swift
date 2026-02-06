//
//  RideCostEstimator.swift
//  NaarsCars
//
//  Utility for estimating ride share costs (Lyft/Uber approximation)
//

import Foundation
import CoreLocation
import MapKit
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Utility for estimating ride share costs
/// Uses a dynamic pricing algorithm with configurable multipliers
enum RideCostEstimator {
    
    // MARK: - Pricing Config
    
    static let pricing = PricingConfig(
        baseFare: 2.50,
        costPerMile: 1.75,
        costPerMinute: 0.35,
        minimumFare: 7.00,
        maximumFare: 150.00,
        weatherTimeoutSeconds: 2.0
    )
    
    static let metersPerMile: Double = 1609.34

    // MARK: - Geocoding Cache Config

    static let geocodingCacheTable = "geocoding_cache"
    static let geocodingCacheTtlHours: Double = 24
    static let geocodingCacheCleanupDays: Int = 7
    static let reverseGeocodeTimeoutSeconds: Double = 2.0
    static let cacheKeyPrecision: Int = 3
    static var geocodingCacheAvailable: Bool?
    
    // MARK: - Zone Definitions
    
    /// Pricing zones are defined as polygons. Add or modify zones here.
    /// Polygons should contain at least 3 points and cover the service area precisely.
    // nonisolated is safe here: immutable let constant of Sendable value type
    nonisolated static let pricingZones: [PricingZone] = [
        PricingZone(
            name: "SeaTac Airport",
            multiplier: 1.3,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.4647, longitude: -122.3088), // North
                CLLocationCoordinate2D(latitude: 47.4605, longitude: -122.2933), // Northeast
                CLLocationCoordinate2D(latitude: 47.4502, longitude: -122.2933), // East
                CLLocationCoordinate2D(latitude: 47.4399, longitude: -122.2933), // Southeast
                CLLocationCoordinate2D(latitude: 47.4357, longitude: -122.3088), // South
                CLLocationCoordinate2D(latitude: 47.4399, longitude: -122.3243), // Southwest
                CLLocationCoordinate2D(latitude: 47.4502, longitude: -122.3243), // West
                CLLocationCoordinate2D(latitude: 47.4605, longitude: -122.3243)  // Northwest
            ]
        ),
        PricingZone(
            name: "Downtown Seattle / Belltown",
            multiplier: 1.3,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.619, longitude: -122.345),
                CLLocationCoordinate2D(latitude: 47.619, longitude: -122.325),
                CLLocationCoordinate2D(latitude: 47.600, longitude: -122.325),
                CLLocationCoordinate2D(latitude: 47.600, longitude: -122.345)
            ]
        ),
        PricingZone(
            name: "Capitol Hill",
            multiplier: 1.2,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.630, longitude: -122.325),
                CLLocationCoordinate2D(latitude: 47.630, longitude: -122.305),
                CLLocationCoordinate2D(latitude: 47.610, longitude: -122.305),
                CLLocationCoordinate2D(latitude: 47.610, longitude: -122.325)
            ]
        ),
        PricingZone(
            name: "University District",
            multiplier: 1.1,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.665, longitude: -122.320),
                CLLocationCoordinate2D(latitude: 47.665, longitude: -122.295),
                CLLocationCoordinate2D(latitude: 47.650, longitude: -122.295),
                CLLocationCoordinate2D(latitude: 47.650, longitude: -122.320)
            ]
        ),
        PricingZone(
            name: "Fremont / Wallingford",
            multiplier: 1.1,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.665, longitude: -122.350),
                CLLocationCoordinate2D(latitude: 47.665, longitude: -122.330),
                CLLocationCoordinate2D(latitude: 47.645, longitude: -122.330),
                CLLocationCoordinate2D(latitude: 47.645, longitude: -122.350)
            ]
        ),
        PricingZone(
            name: "Ballard",
            multiplier: 1.1,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.675, longitude: -122.390),
                CLLocationCoordinate2D(latitude: 47.675, longitude: -122.370),
                CLLocationCoordinate2D(latitude: 47.655, longitude: -122.370),
                CLLocationCoordinate2D(latitude: 47.655, longitude: -122.390)
            ]
        ),
        PricingZone(
            name: "South Lake Union",
            multiplier: 1.2,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.630, longitude: -122.345),
                CLLocationCoordinate2D(latitude: 47.630, longitude: -122.325),
                CLLocationCoordinate2D(latitude: 47.615, longitude: -122.325),
                CLLocationCoordinate2D(latitude: 47.615, longitude: -122.345)
            ]
        ),
        PricingZone(
            name: "Stadium District (Lumen / T-Mobile)",
            multiplier: 1.3,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.6024, longitude: -122.3423),
                CLLocationCoordinate2D(latitude: 47.6024, longitude: -122.3209),
                CLLocationCoordinate2D(latitude: 47.5880, longitude: -122.3209),
                CLLocationCoordinate2D(latitude: 47.5880, longitude: -122.3423)
            ]
        ),
        PricingZone(
            name: "Climate Pledge Arena",
            multiplier: 1.3,
            polygon: [
                CLLocationCoordinate2D(latitude: 47.6292, longitude: -122.3647),
                CLLocationCoordinate2D(latitude: 47.6292, longitude: -122.3433),
                CLLocationCoordinate2D(latitude: 47.6148, longitude: -122.3433),
                CLLocationCoordinate2D(latitude: 47.6148, longitude: -122.3647)
            ]
        )
    ]
    
    // MARK: - Public Methods
    
    /// Estimate ride share cost between two addresses using route calculation.
    /// If route calculation fails, the minimum fare is returned.
    static func estimateCost(pickup: String, destination: String) async -> Double? {
        let estimate = await estimateCostDetails(pickup: pickup, destination: destination)
        return estimate.finalPrice
    }
    
    /// Estimate ride share cost using distance and time with time-of-day adjustments.
    static func estimateCost(distance: Double, timeInMinutes: Double) -> Double {
        let estimate = estimateCostDetails(
            distanceMiles: distance,
            timeMinutes: timeInMinutes,
            date: Date(),
            locationMultiplier: 1.0,
            weatherMultiplier: 1.0,
            calendar: .current
        )
        return estimate.finalPrice
    }
    
    /// Estimate ride share cost between two coordinates using distance/time and location zones.
    static func estimateCost(pickup: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) -> Double {
        let pickupLocation = CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distanceInMeters = pickupLocation.distance(from: destinationLocation)
        let distanceInMiles = distanceInMeters / metersPerMile
        let estimatedMinutes = (distanceInMiles / 30.0) * 60.0
        
        let locationMultiplierValue = locationMultiplier(pickup: pickup, destination: destination)
        
        let estimate = estimateCostDetails(
            distanceMiles: distanceInMiles,
            timeMinutes: estimatedMinutes,
            date: Date(),
            locationMultiplier: locationMultiplierValue,
            weatherMultiplier: 1.0,
            calendar: .current
        )
        return estimate.finalPrice
    }
    
    /// Estimate ride share cost with full pricing breakdown.
    static func estimateCostDetails(
        pickup: String,
        destination: String,
        date: Date = Date(),
        calendar: Calendar = .current
    ) async -> RideCostEstimate {
        let mapService = MapService.shared
        
        async let pickupCoordinate = mapService.geocode(address: pickup)
        async let destinationCoordinate = mapService.geocode(address: destination)
        
        do {
            let pickupCoord = try await pickupCoordinate
            let destCoord = try await destinationCoordinate
            let route = try await mapService.calculateRoute(from: pickupCoord, to: destCoord)
            
            let distanceInMiles = route.distance / metersPerMile
            let timeInMinutes = route.expectedTravelTime / 60
            
            let timeMultiplier = timeOfDayMultiplier(date: date, calendar: calendar)
            async let locationMultiplierValue = locationMultiplier(pickup: pickupCoord, destination: destCoord)
            async let weatherMultiplierValue = weatherMultiplier(for: pickupCoord)
            
            let multipliers = MultiplierBreakdown(
                timeOfDay: timeMultiplier,
                location: await locationMultiplierValue,
                weather: await weatherMultiplierValue
            )
            
            return estimateCostDetails(
                distanceMiles: distanceInMiles,
                timeMinutes: timeInMinutes,
                multipliers: multipliers
            )
        } catch {
            AppLogger.warning("rideCost", "Route calculation failed: \(error.localizedDescription). Returning minimum fare.")
            return fallbackEstimate()
        }
    }
    
    /// Estimate ride share cost with explicit multipliers (useful for testing).
    static func estimateCostDetails(
        distanceMiles: Double,
        timeMinutes: Double,
        date: Date,
        locationMultiplier: Double,
        weatherMultiplier: Double,
        calendar: Calendar = .current
    ) -> RideCostEstimate {
        let timeMultiplier = timeOfDayMultiplier(date: date, calendar: calendar)
        let multipliers = MultiplierBreakdown(
            timeOfDay: timeMultiplier,
            location: locationMultiplier,
            weather: weatherMultiplier
        )
        
        return estimateCostDetails(
            distanceMiles: distanceMiles,
            timeMinutes: timeMinutes,
            multipliers: multipliers
        )
    }
    
    // MARK: - Multiplier Helpers
    
    static func timeOfDayMultiplier(date: Date, calendar: Calendar = .current) -> Double {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        
        let multiplier: Double
        if isWeekend {
            switch hour {
            case 6..<10:
                multiplier = 1.0
            case 10..<17:
                multiplier = 1.1
            case 17..<20:
                multiplier = 1.2
            case 20..<24:
                multiplier = 1.5
            case 0..<3:
                multiplier = 1.7
            case 3..<6:
                multiplier = 1.5
            default:
                multiplier = 1.0
            }
        } else {
            switch hour {
            case 7..<9:
                multiplier = 1.5
            case 9..<17:
                multiplier = 1.0
            case 17..<19:
                multiplier = 1.6
            case 19..<22:
                multiplier = 1.2
            case 22..<24, 0..<2:
                multiplier = 1.3
            case 2..<6:
                multiplier = 1.4
            case 6..<7:
                multiplier = 1.1
            default:
                multiplier = 1.0
            }
        }
        
        AppLogger.info("rideCost", "Time-of-day multiplier: \(multiplier) (hour: \(hour), weekend: \(isWeekend))")
        return multiplier
    }
    
    private static func zoneMultiplierResult(
        pickup: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        zones: [PricingZone]
    ) -> (multiplier: Double, matchedZones: [String]) {
        var maxMultiplier = 1.0
        var matchedZones: [String] = []

        for zone in zones {
            let pickupInside = isCoordinate(pickup, in: zone.polygon)
            let destinationInside = isCoordinate(destination, in: zone.polygon)

            if pickupInside || destinationInside {
                maxMultiplier = max(maxMultiplier, zone.multiplier)
                matchedZones.append(zone.name)
            }
        }

        return (maxMultiplier, matchedZones)
    }

    @MainActor
    static func locationMultiplier(
        pickup: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        zones: [PricingZone] = pricingZones
    ) -> Double {
        let result = zoneMultiplierResult(pickup: pickup, destination: destination, zones: zones)
        AppLogger.info("rideCost", "Location multiplier: \(result.multiplier) (zones: \(result.matchedZones))")
        return result.multiplier
    }

    @MainActor
    static func locationMultiplier(
        pickup: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        zones: [PricingZone] = pricingZones
    ) async -> Double {
        let result = zoneMultiplierResult(pickup: pickup, destination: destination, zones: zones)

        if result.multiplier > 1.0 {
            AppLogger.info("rideCost", "Location multiplier: \(result.multiplier) (zones: \(result.matchedZones))")
            return result.multiplier
        }

        async let pickupMultiplier = getReverseGeocodedMultiplier(coordinate: pickup)
        async let destinationMultiplier = getReverseGeocodedMultiplier(coordinate: destination)
        let fallbackMultiplier = max(await pickupMultiplier, await destinationMultiplier)

        AppLogger.info("rideCost", "Location multiplier: \(fallbackMultiplier) (reverse geocoded)")
        return fallbackMultiplier
    }

    static func weatherMultiplier(for category: WeatherCategory) -> Double {
        let multiplier: Double
        switch category {
        case .heavyPrecipitation:
            multiplier = 1.2
        case .lightPrecipitation:
            multiplier = 1.1
        case .clear:
            multiplier = 1.0
        }
        
        AppLogger.info("rideCost", "Weather multiplier: \(multiplier) (category: \(category))")
        return multiplier
    }
    
    // MARK: - Internal Helpers
    
    private static func estimateCostDetails(
        distanceMiles: Double,
        timeMinutes: Double,
        multipliers: MultiplierBreakdown
    ) -> RideCostEstimate {
        let basePrice = calculateBasePrice(distanceMiles: distanceMiles, timeMinutes: timeMinutes)
        let totalMultiplier = multipliers.timeOfDay * multipliers.location * multipliers.weather
        let adjustedPrice = basePrice * totalMultiplier
        let finalPrice = applyFareCaps(adjustedPrice)
        
        AppLogger.info("rideCost", "Base price: \(roundToTwoDecimals(basePrice))")
        AppLogger.info("rideCost", "Total multiplier: \(roundToTwoDecimals(totalMultiplier))")
        AppLogger.info("rideCost", "Final price: \(roundToTwoDecimals(finalPrice))")
        
        return RideCostEstimate(
            finalPrice: roundToTwoDecimals(finalPrice),
            totalMultiplier: roundToTwoDecimals(totalMultiplier),
            estimatedTimeMinutes: roundToTwoDecimals(timeMinutes),
            distanceMiles: roundToTwoDecimals(distanceMiles),
            multipliers: multipliers
        )
    }
    
    private static func calculateBasePrice(distanceMiles: Double, timeMinutes: Double) -> Double {
        pricing.baseFare + (distanceMiles * pricing.costPerMile) + (timeMinutes * pricing.costPerMinute)
    }
    
    private static func applyFareCaps(_ value: Double) -> Double {
        let withMinimum = max(pricing.minimumFare, value)
        return min(withMinimum, pricing.maximumFare)
    }
    
    private static func roundToTwoDecimals(_ value: Double) -> Double {
        round(value * 100) / 100
    }
    
    private static func fallbackEstimate() -> RideCostEstimate {
        let multipliers = MultiplierBreakdown(timeOfDay: 1.0, location: 1.0, weather: 1.0)
        return RideCostEstimate(
            finalPrice: roundToTwoDecimals(pricing.minimumFare),
            totalMultiplier: 1.0,
            estimatedTimeMinutes: 0.0,
            distanceMiles: 0.0,
            multipliers: multipliers
        )
    }
    
    private static func isCoordinate(_ coordinate: CLLocationCoordinate2D, in polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        
        var isInside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].longitude
            let yi = polygon[i].latitude
            let xj = polygon[j].longitude
            let yj = polygon[j].latitude
            
            let intersects = ((yi > coordinate.latitude) != (yj > coordinate.latitude)) &&
                (coordinate.longitude < (xj - xi) * (coordinate.latitude - yi) / (yj - yi) + xi)
            
            if intersects {
                isInside.toggle()
            }
            
            j = i
        }
        
        return isInside
    }
    
    // MARK: - Weather
    
    private static func weatherMultiplier(for coordinate: CLLocationCoordinate2D) async -> Double {
        #if canImport(WeatherKit)
        if #available(iOS 16.0, *) {
            let result = await withTimeout(seconds: pricing.weatherTimeoutSeconds) {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let weather = try await WeatherService.shared.weather(for: location)
                let category = weatherCategory(for: weather.currentWeather.condition)
                return weatherMultiplier(for: category)
            }
            
            if let result {
                return result
            }
            
            AppLogger.warning("rideCost", "Weather lookup timed out. Defaulting to 1.0.")
        } else {
            AppLogger.warning("rideCost", "WeatherKit unavailable on this OS. Defaulting to 1.0.")
        }
        #endif
        
        return 1.0
    }
    
    static func withTimeout<T>(
        seconds: Double,
        operation: @escaping () async throws -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                do {
                    return try await operation()
                } catch {
                    return nil
                }
            }
            
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }
            
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
    
    #if canImport(WeatherKit)
    @available(iOS 16.0, *)
    private static func weatherCategory(for condition: WeatherCondition) -> WeatherCategory {
        let conditionName = String(describing: condition).lowercased()
        
        if conditionName.contains("heavy") || conditionName.contains("thunder") || conditionName.contains("hurricane") {
            return .heavyPrecipitation
        }
        
        if conditionName.contains("rain") || conditionName.contains("drizzle") || conditionName.contains("snow") {
            return .lightPrecipitation
        }
        
        return .clear
    }
    #endif
    
    /// Format cost for display
    /// - Parameter cost: Cost in USD
    /// - Returns: Formatted string (e.g., "$12.50")
    static func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: cost)) ?? "$\(String(format: "%.2f", cost))"
    }
}

