//
//  RideCostEstimator.swift
//  NaarsCars
//
//  Utility for estimating ride share costs (Lyft/Uber approximation)
//

import Foundation
import CoreLocation
import MapKit

/// Utility for estimating ride share costs
/// Uses a simplified pricing algorithm based on distance and base rates
enum RideCostEstimator {
    
    // MARK: - Pricing Constants
    
    /// Base fare for a ride (in USD)
    private static let baseFare: Double = 2.55
    
    /// Cost per mile (in USD)
    private static let costPerMile: Double = 1.50
    
    /// Cost per minute (in USD)
    private static let costPerMinute: Double = 0.25
    
    /// Minimum fare (in USD)
    private static let minimumFare: Double = 5.00
    
    /// Maximum fare cap for estimation (in USD)
    private static let maximumFare: Double = 150.00
    
    // MARK: - Public Methods
    
    /// Estimate ride share cost between two addresses using route calculation
    /// - Parameters:
    ///   - pickup: Pickup address string
    ///   - destination: Destination address string
    /// - Returns: Estimated cost in USD, or nil if estimation fails
    static func estimateCost(pickup: String, destination: String) async -> Double? {
        // Geocode both addresses
        let mapService = MapService.shared
        
        async let pickupCoordinate = mapService.geocode(address: pickup)
        async let destinationCoordinate = mapService.geocode(address: destination)
        
        do {
            let pickupCoord = try await pickupCoordinate
            let destCoord = try await destinationCoordinate
            
            // Calculate route for more accurate distance and time
            let route = try await mapService.calculateRoute(from: pickupCoord, to: destCoord)
            
            // Use route distance and time for cost calculation
            let distanceInMiles = route.distance / 1609.34 // Convert meters to miles
            let timeInMinutes = route.expectedTravelTime / 60 // Convert seconds to minutes
            
            return estimateCost(distance: distanceInMiles, timeInMinutes: timeInMinutes)
        } catch {
            // If geocoding or routing fails, return nil
            return nil
        }
    }
    
    /// Estimate ride share cost using distance and time
    /// - Parameters:
    ///   - distance: Distance in miles
    ///   - timeInMinutes: Travel time in minutes
    /// - Returns: Estimated cost in USD
    static func estimateCost(distance: Double, timeInMinutes: Double) -> Double {
        // Calculate cost components
        let distanceCost = distance * costPerMile
        let timeCost = timeInMinutes * costPerMinute
        let totalCost = baseFare + distanceCost + timeCost
        
        // Apply minimum and maximum caps
        let cappedCost = max(minimumFare, min(totalCost, maximumFare))
        
        // Round to 2 decimal places
        return round(cappedCost * 100) / 100
    }
    
    /// Estimate ride share cost between two coordinates
    /// - Parameters:
    ///   - pickup: Pickup coordinate
    ///   - destination: Destination coordinate
    /// - Returns: Estimated cost in USD
    static func estimateCost(pickup: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) -> Double {
        // Calculate distance in miles
        let pickupLocation = CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distanceInMeters = pickupLocation.distance(from: destinationLocation)
        let distanceInMiles = distanceInMeters / 1609.34 // Convert meters to miles
        
        // Estimate drive time (assuming average speed of 30 mph in urban areas)
        let estimatedMinutes = (distanceInMiles / 30.0) * 60.0
        
        // Calculate cost components
        let distanceCost = distanceInMiles * costPerMile
        let timeCost = estimatedMinutes * costPerMinute
        let totalCost = baseFare + distanceCost + timeCost
        
        // Apply minimum and maximum caps
        let cappedCost = max(minimumFare, min(totalCost, maximumFare))
        
        // Round to 2 decimal places
        return round(cappedCost * 100) / 100
    }
    
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

