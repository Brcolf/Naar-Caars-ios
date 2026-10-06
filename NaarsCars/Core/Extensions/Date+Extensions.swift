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
    
    /// True for anything less than a minute from the device clock in either direction. A row
    /// created a moment ago carries a server timestamp that is often slightly ahead of the
    /// device, which the relative formatter spelled as "in 0 seconds".
    private var isWithinAMinuteOfNow: Bool {
        abs(timeIntervalSinceNow) < 60
    }

    /// Human-readable time ago string (e.g., "now", "2 hours ago", "3 days ago")
    var timeAgo: String {
        if isWithinAMinuteOfNow {
            return DateFormatters.nowFormatter.localizedString(fromTimeInterval: 0)
        }
        return DateFormatters.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Short time ago string for messages (e.g., "now", "2h ago", "3d ago")
    var timeAgoString: String {
        if isWithinAMinuteOfNow {
            return DateFormatters.nowFormatter.localizedString(fromTimeInterval: 0)
        }
        return DateFormatters.abbreviatedRelativeFormatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Formats a Postgres `time` string ("09:00:00" / "09:00") as a localized short time
    /// ("9:00 AM"). Falls back to the raw string when it does not parse.
    static func displayTime(fromDatabaseTime raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return raw }
        var components = DateComponents()
        components.hour = parts[0]
        components.minute = parts[1]
        guard let date = Calendar.current.date(from: components) else { return raw }
        return DateFormatters.timeFormatter.string(from: date)
    }

    /// Formatted time string (e.g., "2:30 PM")
    var timeString: String {
        DateFormatters.timeFormatter.string(from: self)
    }
    
    /// Conversation-list timestamp, iMessage style: the time today ("2:30 PM"), "Yesterday",
    /// the weekday within the last week, otherwise a short date ("1/15/25").
    var conversationListTimestampString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return timeString
        }
        if calendar.isDateInYesterday(self) {
            return "messaging_yesterday".localized
        }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: Date())
        ).day ?? Int.max
        if days > 0 && days < 7 {
            return DateFormatters.dayOfWeekFormatter.string(from: self)
        }
        return DateFormatters.shortDateFormatter.string(from: self)
    }

    /// Messaging timestamp string (e.g., "10:30 AM", "Yesterday 10:30 AM")
    var messageTimestampString: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(self) {
            return timeString
        }
        if calendar.isDateInYesterday(self) {
            return "\("messaging_yesterday".localized) \(timeString)"
        }
        if calendar.isDate(self, equalTo: now, toGranularity: .weekOfYear) {
            // Joined by hand: the weekday+time template puts the weekday in parentheses in Korean.
            return "\(DateFormatters.dayOfWeekFormatter.string(from: self)) \(timeString)"
        }
        // One template per dated case, so each locale orders and joins the date and the time
        // itself ("Jan 15 at 2:30 PM", "1월 15일 오후 2:30") instead of gluing an English-order
        // date to the time with a comma.
        if calendar.isDate(self, equalTo: now, toGranularity: .year) {
            return DateFormatters.monthDayTimeFormatter.string(from: self)
        }

        return DateFormatters.monthDayYearTimeFormatter.string(from: self)
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

