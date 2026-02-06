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
    
    enum BannerStyle {
        case error
        case warning
        case info
        
        var backgroundColor: Color {
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
            
            Text(message)
                .font(.naarsSubheadline)
                .lineLimit(2)
            
            Spacer()
            
            if let retryAction {
                Button(action: retryAction) {
                    Text("Retry")
                        .font(.naarsSubheadline)
                        .fontWeight(.semibold)
                        .underline()
                }
            }
            
            if let dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.naarsCaption)
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, Constants.Spacing.sm)
        .background(style.backgroundColor)
        .cornerRadius(Constants.Spacing.sm)
        .padding(.horizontal, Constants.Spacing.md)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                errorMessage = nil
                            }
                        }
                    )
                    .padding(.top, Constants.Spacing.sm)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: errorMessage != nil)
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
