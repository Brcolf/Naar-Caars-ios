//
//  TimeZonePicker.swift
//  NaarsCars
//
//  Timezone picker for request creation/editing and community settings
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
            ForEach(Self.options(including: selectedTimezone), id: \.id) { tz in
                Text(tz.label).tag(tz.id)
            }
        }
    }

    /// The six zones, plus `selected` when it is a valid identifier not among them (a community
    /// created in `Europe/Berlin` or `America/Phoenix`), so the picker never shows a blank value.
    /// An off-list zone whose generic name repeats one already listed ("Mountain Time" for
    /// Phoenix) uses its standard name instead ("Mountain Standard Time").
    static func options(including selected: String) -> [(id: String, label: String)] {
        var result = timezones.map { (id: $0.id, label: displayName(for: $0)) }
        guard !timezones.contains(where: { $0.id == selected }),
              let zone = TimeZone(identifier: selected) else {
            return result
        }
        let locale = LocalizationManager.shared.currentLocale
        var label = zone.localizedName(for: .generic, locale: locale) ?? selected
        if result.contains(where: { $0.label == label }) {
            label = zone.localizedName(for: .standard, locale: locale) ?? selected
        }
        result.append((id: selected, label: label))
        return result
    }

    /// The name shown for a zone identifier where it cannot be changed (a read-only setting):
    /// the same label the picker would show, or the identifier itself when no name is known.
    static func displayName(forIdentifier identifier: String) -> String {
        options(including: identifier).first { $0.id == identifier }?.label ?? identifier
    }

    /// The system's name for the zone in the app's language ("Pacific Time", "太平洋时间"),
    /// falling back to the English label above.
    private static func displayName(for tz: (id: String, label: String)) -> String {
        TimeZone(identifier: tz.id)?
            .localizedName(for: .generic, locale: LocalizationManager.shared.currentLocale)
            ?? tz.label
    }
}
