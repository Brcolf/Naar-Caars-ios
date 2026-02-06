//
//  ShakeModifier.swift
//  NaarsCars
//
//  Shake animation modifier for invalid input feedback
//

import SwiftUI

/// Shake animation modifier for error feedback on text fields
struct ShakeModifier: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: amount * sin(animatableData * .pi * shakesPerUnit),
            y: 0
        ))
    }
}

extension View {
    /// Apply a shake animation, triggered by incrementing the shake count
    func shake(trigger: Int) -> some View {
        modifier(ShakeModifier(animatableData: CGFloat(trigger)))
    }
}
