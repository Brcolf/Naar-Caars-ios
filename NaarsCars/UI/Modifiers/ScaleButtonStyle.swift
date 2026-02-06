//
//  ScaleButtonStyle.swift
//  NaarsCars
//
//  Button press animation that scales down slightly on press
//

import SwiftUI

/// Button style that provides a subtle scale-down animation on press
struct ScaleButtonStyle: ButtonStyle {
    let scaleAmount: CGFloat
    
    init(scaleAmount: CGFloat = 0.96) {
        self.scaleAmount = scaleAmount
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ScaleButtonStyle {
    /// Subtle scale-down animation on button press
    static var scale: ScaleButtonStyle { ScaleButtonStyle() }
    
    /// Custom scale amount for button press animation
    static func scale(_ amount: CGFloat) -> ScaleButtonStyle {
        ScaleButtonStyle(scaleAmount: amount)
    }
}
