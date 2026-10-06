//
//  TimeZonePicker.swift
//  NaarsCars
//
//  Timezone picker for request creation/editing
//

import SwiftUI

struct TimeZonePicker: View {
    @Binding var selectedTimezone: String

    private static let timezones: [(id: String, label: String)] = [
        ("America/Los_Angeles", "Pacific Time"),
        ("America/Denver", "Mountain Time"),
        ("America/Chicago", "Central Time"),
        ("America/New_York", "Eastern Time"),
        ("Pacific/Honolulu", "Hawaii Time"),
        ("America/Anchorage", "Alaska Time"),
    ]

    var body: some View {
        Picker("timezone_picker_label".localized, selection: $selectedTimezone) {
            ForEach(Self.timezones, id: \.id) { tz in
                Text(Self.displayName(for: tz)).tag(tz.id)
            }
        }
    }

    /// The system's name for the zone in the app's language ("Pacific Time", "太平洋时间"),
    /// falling back to the English label above.
    private static func displayName(for tz: (id: String, label: String)) -> String {
        TimeZone(identifier: tz.id)?
            .localizedName(for: .generic, locale: LocalizationManager.shared.currentLocale)
            ?? tz.label
    }
}
