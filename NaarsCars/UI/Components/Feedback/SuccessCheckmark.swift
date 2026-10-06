//
//  SuccessCheckmark.swift
//  NaarsCars
//
//  Animated success checkmark for confirmation feedback
//

import SwiftUI

/// Animated checkmark that draws itself when shown
struct SuccessCheckmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    let size: CGFloat
    let color: Color
    let onComplete: (() -> Void)?
    
    init(size: CGFloat = 60, color: Color = .naarsSuccess, onComplete: (() -> Void)? = nil) {
        self.size = size
        self.color = color
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(scale)
            
            Circle()
                .stroke(color, lineWidth: 3)
                .frame(width: size, height: size)
                .scaleEffect(scale)
            
            CheckmarkShape()
                .trim(from: 0, to: trimEnd)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.45, height: size * 0.45)
                .scaleEffect(scale)
        }
        .opacity(opacity)
        // Three unlabeled shapes otherwise; VoiceOver reads the mark as "Done".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("common_done".localized)
        .onAppear {
            if reduceMotion {
                // Reduce Motion: fade the finished mark in instead of springing and drawing it.
                scale = 1.0
                trimEnd = 1.0
                withAnimation(.naarsQuick) {
                    opacity = 1
                }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    scale = 1.0
                    opacity = 1
                }
                withAnimation(.easeInOut(duration: 0.3).delay(0.2)) {
                    trimEnd = 1.0
                }
            }
            HapticManager.success()
            // VoiceOver users otherwise get only the haptic.
            AccessibilityAnnouncer.announce("common_done".localized)

            if let onComplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.naarsQuick) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                }
            }
        }
    }
}

/// Checkmark shape for the animation
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.05, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.15))
        
        return path
    }
}

/// View modifier to show a success checkmark overlay
struct SuccessCheckmarkModifier: ViewModifier {
    @Binding var isShowing: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        SuccessCheckmark {
                            isShowing = false
                        }
                    }
                }
            }
    }
}

extension View {
    /// Show an animated success checkmark overlay
    func successCheckmark(isShowing: Binding<Bool>) -> some View {
        modifier(SuccessCheckmarkModifier(isShowing: isShowing))
    }
}

#Preview {
    SuccessCheckmark()
}
