//
//  Date+Localization.swift
//  NaarsCars
//
//  Extension for locale-aware date formatting
//

import Foundation

extension Date {
    /// Locale-aware short date (e.g., "Jan 5" or "5 Jan")
    var localizedShortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
    
    /// Locale-aware time (e.g., "2:30 PM" or "14:30")
    var localizedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
    
    /// Locale-aware relative time (e.g., "2 hours ago", "in 3 days")
    var localizedRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Full date/time for display
    var localizedFull: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
    
    /// Date and time combined (e.g., "Jan 5, 2025 at 2:30 PM")
    var localizedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
}

