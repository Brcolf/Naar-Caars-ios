//
//  DateFormatters.swift
//  NaarsCars
//
//  Shared, thread-safe date formatters for consistent formatting
//  DateFormatter creation is expensive - these cached instances improve performance
//

import Foundation

/// Shared date formatters for consistent formatting throughout the app
/// All formatters are lazily initialized and thread-safe
enum DateFormatters {
    
    // MARK: - Display Formatters
    
    /// Time-only formatter (e.g., "2:30 PM")
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    
    /// Date-only formatter (e.g., "Jan 15, 2025")
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    /// Date and time formatter (e.g., "Jan 15, 2025 at 2:30 PM")
    static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Short date formatter (e.g., "1/15/25")
    static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    /// Full date formatter (e.g., "Wednesday, January 15, 2025")
    static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
    
    // MARK: - Relative Formatters
    
    /// Relative time formatter with full units (e.g., "2 hours ago", "3 days ago")
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    /// Relative time formatter with abbreviated units (e.g., "2h ago", "3d ago")
    static let abbreviatedRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    // MARK: - ISO8601 Formatters (for API communication)
    
    /// ISO8601 formatter with fractional seconds (Supabase format)
    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Standard ISO8601 formatter
    static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    // MARK: - Custom Format Formatters
    
    /// Date-only formatter for API (YYYY-MM-DD format)
    /// Uses local timezone to match what users select in DatePicker
    /// This ensures dates don't shift by a day due to timezone conversion
    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current  // Use local timezone to avoid off-by-one day issues
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Month and year formatter (e.g., "January 2025")
    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    /// Day of week formatter (e.g., "Monday")
    static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

