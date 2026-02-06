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
    
    var backgroundColor: Color {
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
    
    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: style.iconName)
                .font(.naarsBody)
            
            Text(message)
                .font(.naarsSubheadline)
                .lineLimit(2)
        }
        .foregroundColor(.white)
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, 10)
        .background(style.backgroundColor)
        .cornerRadius(Constants.Spacing.sm)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// View modifier that shows a toast overlay
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    var style: ToastStyle
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let msg = message {
                    ToastView(message: msg, style: style)
                        .padding(.horizontal, Constants.Spacing.md)
                        .padding(.top, Constants.Spacing.sm)
                        .onAppear {
                            HapticManager.success()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    message = nil
                                }
                            }
                        }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: message != nil)
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
