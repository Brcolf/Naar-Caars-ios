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
    
    /// Spells a zero interval as "now" in the user's language. Used for anything under a minute old.
    static let nowFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
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
    
    // The display formatters below are built from templates, not fixed patterns: a template
    // gives each locale its own field order and markers ("Jan 15", "15 ene", "1월 15일"),
    // where a fixed "MMM d" printed translated month names in English order.

    /// Month and year formatter (e.g., "January 2025")
    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter
    }()

    /// Abbreviated month and year formatter (e.g., "Jan 2025")
    static let abbreviatedMonthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return formatter
    }()

    /// Day of week formatter (e.g., "Monday")
    static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    /// Month and day formatter (e.g., "Jan 15")
    static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// Month, day, and year formatter (e.g., "Jan 15, 2025")
    static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    /// Month, day and time formatter (e.g., "Jan 15 at 2:30 PM"); "j" follows the 12/24-hour setting
    static let monthDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter
    }()

    /// Month, day, year and time formatter (e.g., "Jan 15, 2025 at 2:30 PM")
    static let monthDayYearTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
        return formatter
    }()

    // MARK: - Server period labels

    /// Parses the English "Mon YYYY" label that the `get_user_savings` RPC builds with `to_char`.
    /// Parsing only; never shown.
    private static let serverMonthYearParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// A savings period label from `get_user_savings` ("Oct 2026", "2026" or "All Time") in the
    /// user's language. The server sends English text and no period date, so the month form is
    /// parsed back and reformatted; anything unrecognized is returned unchanged.
    static func displayLabel(forSavingsPeriod serverLabel: String) -> String {
        if serverLabel == "All Time" {
            return "period_all_time".localized
        }
        if let monthStart = serverMonthYearParser.date(from: serverLabel) {
            return abbreviatedMonthYearFormatter.string(from: monthStart)
        }
        return serverLabel
    }
}

