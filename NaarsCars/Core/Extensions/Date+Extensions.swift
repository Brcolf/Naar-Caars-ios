//
//  Date+Extensions.swift
//  NaarsCars
//
//  Date helper methods and formatting extensions
//  Uses shared DateFormatters for performance
//

import Foundation

extension Date {
    /// Whether this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    /// Human-readable time ago string (e.g., "2 hours ago", "3 days ago")
    var timeAgo: String {
        DateFormatters.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Short time ago string for messages (e.g., "2h ago", "3d ago")
    var timeAgoString: String {
        DateFormatters.abbreviatedRelativeFormatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Formatted time string (e.g., "2:30 PM")
    var timeString: String {
        DateFormatters.timeFormatter.string(from: self)
    }
    
    /// Formatted date string (e.g., "Jan 15, 2025")
    var dateString: String {
        DateFormatters.dateFormatter.string(from: self)
    }
    
    /// Formatted date and time string (e.g., "Jan 15, 2025 at 2:30 PM")
    var dateTimeString: String {
        DateFormatters.dateTimeFormatter.string(from: self)
    }
    
    /// Short formatted date string (e.g., "1/15/25")
    var shortDateString: String {
        DateFormatters.shortDateFormatter.string(from: self)
    }
    
    /// Month and year string (e.g., "January 2025")
    var monthYearString: String {
        DateFormatters.monthYearFormatter.string(from: self)
    }
}

