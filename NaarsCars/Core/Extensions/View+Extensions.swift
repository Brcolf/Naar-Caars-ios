//
//  View+Extensions.swift
//  NaarsCars
//
//  SwiftUI view extensions for common modifiers
//

import SwiftUI
import UIKit

extension View {
    /// The one card recipe: 16 pt padding, the card surface, the card radius and the card shadow.
    func cardStyle() -> some View {
        self
            .padding()
            .cardSurface()
    }

    /// Card surface without padding, for content that manages its own insets.
    func cardSurface() -> some View {
        self
            .background(Color.naarsCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.card, style: .continuous))
            .cardShadow()
    }

    /// Resting elevation for cards. Black, so it disappears in dark mode instead of glowing.
    func cardShadow() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    /// Elevation for anything that floats above content: toasts, banners, map pins.
    func floatingShadow() -> some View {
        shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
    }
    
    /// Apply section header style
    func sectionHeaderStyle() -> some View {
        self
            .font(.naarsHeadline)
            .foregroundColor(.naarsTextPrimary)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
}

// MARK: - Motion

extension Animation {
    /// State changes, banners, expand and collapse
    static let naarsStandard = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Dismissals and fades
    static let naarsQuick = Animation.easeOut(duration: Constants.Animation.short)

    /// Press feedback on buttons
    static let naarsPress = Animation.spring(response: 0.2, dampingFraction: 0.7)
}

// MARK: - Accessibility-size layouts

/// A row that is side by side at standard Dynamic Type sizes and stacked (leading-aligned) at
/// accessibility sizes, where two columns or a title-plus-hint row collapse to one word per
/// line ("Ro / ute", "Ja / n / 21"). Use `AdaptiveRowSpacer` instead of `Spacer()` inside it.
struct AdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    var stackedSpacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: stackedSpacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content() }
    }
}

/// `Spacer()` at standard sizes; nothing when the enclosing `AdaptiveRow` is stacked.
struct AdaptiveRowSpacer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Spacer()
        }
    }
}

// MARK: - VoiceOver announcements

/// Speaks a transient status change (a toast, the success checkmark, an error banner, the
/// offline notice) to VoiceOver users, who otherwise get only the haptic.
enum AccessibilityAnnouncer {
    @MainActor
    static func announce(_ message: String) {
        guard !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

// MARK: - Bundle Extension

extension Bundle {
    /// App version string (e.g., "1.0.0")
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    /// Build number string
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    /// Full version string (e.g., "1.0.0 (42)")
    var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }
}