//
//  ErrorBanner.swift
//  NaarsCars
//
//  Non-blocking error banner that appears at the top of the screen
//

import SwiftUI

/// A non-blocking error banner with optional retry action
struct ErrorBanner: View {
    let message: String
    let style: BannerStyle
    var retryAction: (() -> Void)?
    var dismissAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum BannerStyle {
        case error
        case warning
        case info
        
        /// Color of the icon. The banner itself is neutral glass.
        var tintColor: Color {
            switch self {
            case .error: return Color.naarsError
            case .warning: return Color.naarsWarning
            case .info: return Color.naarsPrimary
            }
        }
        
        var iconName: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    init(
        message: String,
        style: BannerStyle = .error,
        retryAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.retryAction = retryAction
        self.dismissAction = dismissAction
    }
    
    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: style.iconName)
                .font(.naarsBody)
                .foregroundColor(style.tintColor)
                .accessibilityHidden(true)
            
            Text(message)
                .font(.naarsSubheadline)
                .foregroundColor(.primary)
                // At accessibility text sizes two lines hold only a few words: show all of it.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            
            Spacer()
            
            if let retryAction {
                Button(action: retryAction) {
                    Text("common_retry".localized)
                        .font(.naarsSubheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.naarsPrimary)
                        .frame(minHeight: 44)
                }
            }
            
            if let dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 32, minHeight: 44)
                }
                .accessibilityLabel("common_close".localized)
            }
        }
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, Constants.Spacing.xs)
        .glassEffect(.regular, in: .rect(cornerRadius: Constants.Radius.card))
        .padding(.horizontal, Constants.Spacing.md)
        // A failure that only appears on screen is silent for VoiceOver users. Announced here,
        // not in the modifier, so a banner placed directly in a view is spoken too.
        .onAppear { AccessibilityAnnouncer.announce(message) }
        .onChange(of: message) { _, newMessage in AccessibilityAnnouncer.announce(newMessage) }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// View modifier to show an error banner overlay
struct ErrorBannerModifier: ViewModifier {
    @Binding var errorMessage: String?
    var style: ErrorBanner.BannerStyle
    var retryAction: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = errorMessage {
                    ErrorBanner(
                        message: message,
                        style: style,
                        retryAction: retryAction,
                        dismissAction: { 
                            withAnimation(.naarsStandard) {
                                errorMessage = nil
                            }
                        }
                    )
                    .padding(.top, Constants.Spacing.sm)
                }
            }
            .animation(.naarsStandard, value: errorMessage != nil)
    }
}

extension View {
    /// Show a non-blocking error banner at the top of the view
    func errorBanner(
        message: Binding<String?>,
        style: ErrorBanner.BannerStyle = .error,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorBannerModifier(
            errorMessage: message,
            style: style,
            retryAction: retryAction
        ))
    }
}

#Preview {
    VStack {
        ErrorBanner(
            message: "Failed to load data. Please check your connection.",
            retryAction: {},
            dismissAction: {}
        )
        
        Spacer()
    }
}
