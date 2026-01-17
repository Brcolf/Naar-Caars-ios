//
//  Number+Localization.swift
//  NaarsCars
//
//  Extension for locale-aware number formatting
//

import Foundation

extension Int {
    /// Locale-aware number string (e.g., "1,000" or "1.000")
    var localizedString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Double {
    /// Locale-aware decimal string
    /// - Parameter decimals: Number of decimal places (default: 1)
    /// - Returns: Formatted string
    func localizedString(decimals: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "%.\(decimals)f", self)
    }
    
    /// Rating display (e.g., "4.8")
    var localizedRating: String {
        return localizedString(decimals: 1)
    }
}


