//
//  ToastView.swift
//  NaarsCars
//
//  Lightweight toast notification that slides in from top and auto-dismisses
//

import SwiftUI

/// Toast style determines icon and color
enum ToastStyle {
    case success
    case info
    case warning
    
    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }
    
    /// Color of the icon. The toast itself is neutral glass so the message reads in both appearances.
    var tintColor: Color {
        switch self {
        case .success: return Color.naarsSuccess
        case .info: return Color.naarsPrimary
        case .warning: return Color.naarsWarning
        }
    }
}

/// Lightweight toast that slides in from top and auto-dismisses
struct ToastView: View {
    let message: String
    let style: ToastStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: style.iconName)
                .font(.naarsBody)
                .foregroundColor(style.tintColor)
                .accessibilityHidden(true)

            Text(message)
                .font(.naarsSubheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                // At accessibility text sizes two lines hold only a few words: show all of it.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, 10)
        // Floating, transient chrome: the same glass as the tab bar and toolbar buttons. The
        // button radius draws a capsule at one or two lines and a rounded box once the text
        // wraps further, so the shape never cuts into the message.
        .glassEffect(.regular, in: .rect(cornerRadius: Constants.Radius.button))
    }
}

/// View modifier that shows a toast overlay
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var style: ToastStyle
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let msg = message {
                    ToastView(message: msg, style: style)
                        .padding(.horizontal, Constants.Spacing.md)
                        .padding(.top, Constants.Spacing.sm)
                }
            }
            .animation(.naarsStandard, value: message != nil)
            // Keyed on the message, not on the toast appearing, so a message that replaces a
            // visible toast gets its own haptic, announcement and full display time.
            .task(id: message) {
                guard let msg = message else { return }
                switch style {
                case .success: HapticManager.success()
                case .warning: HapticManager.error()
                case .info: break
                }
                // VoiceOver users otherwise get only the haptic.
                AccessibilityAnnouncer.announce(msg)
                try? await Task.sleep(nanoseconds: UInt64(displayDuration(for: msg) * 1_000_000_000))
                // The sleep also ends early when the message changes (the new one has its own
                // task) or the screen goes away (clear it so it does not come back with the screen).
                guard message == msg else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    message = nil
                }
            }
    }

    /// Two seconds for a short confirmation, longer for a longer message, and longer again
    /// while VoiceOver is running so the dismissal does not outrun the spoken announcement.
    private func displayDuration(for text: String) -> TimeInterval {
        let readingTime = TimeInterval(text.count) * Constants.Timing.toastDurationPerCharacter
        let duration = min(
            max(Constants.Timing.toastMinimumDuration, readingTime),
            Constants.Timing.toastMaximumDuration
        )
        return voiceOverEnabled ? duration * Constants.Timing.toastVoiceOverDurationMultiplier : duration
    }
}

extension View {
    /// Show a lightweight toast notification at the top of the view
    func toast(message: Binding<String?>, style: ToastStyle = .success) -> some View {
        modifier(ToastModifier(message: message, style: style))
    }
}

#Preview {
    VStack {
        ToastView(message: "Comment posted", style: .success)
        ToastView(message: "Message edited", style: .info)
        ToastView(message: "Connection lost", style: .warning)
    }
    .padding()
}
