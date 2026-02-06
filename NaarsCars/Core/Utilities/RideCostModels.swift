//
//  RideCostModels.swift
//  NaarsCars
//
//  Model types used by RideCostEstimator
//

import Foundation
import CoreLocation

// MARK: - RideCostEstimator Model Types

extension RideCostEstimator {
    
    struct MultiplierBreakdown {
        let timeOfDay: Double
        let location: Double
        let weather: Double
    }
    
    struct RideCostEstimate {
        let finalPrice: Double
        let totalMultiplier: Double
        let estimatedTimeMinutes: Double
        let distanceMiles: Double
        let multipliers: MultiplierBreakdown
    }
    
    struct PricingZone {
        let name: String
        let multiplier: Double
        let polygon: [CLLocationCoordinate2D]
    }
    
    enum WeatherCategory {
        case clear
        case lightPrecipitation
        case heavyPrecipitation
    }
    
    // MARK: - Pricing Config
    
    struct PricingConfig {
        let baseFare: Double
        let costPerMile: Double
        let costPerMinute: Double
        let minimumFare: Double
        let maximumFare: Double
        let weatherTimeoutSeconds: Double
    }
}
