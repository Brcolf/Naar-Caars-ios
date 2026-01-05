//
//  Date+Extensions.swift
//  NaarsCars
//
//  Date helper methods and formatting extensions
//

import Foundation

extension Date {
    /// Whether this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    /// Human-readable time ago string (e.g., "2 hours ago", "3 days ago")
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Formatted time string (e.g., "2:30 PM")
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Formatted date string (e.g., "Jan 15, 2025")
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    /// Formatted date and time string (e.g., "Jan 15, 2025 at 2:30 PM")
    var dateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

