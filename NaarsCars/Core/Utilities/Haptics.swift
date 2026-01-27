//
//  Haptics.swift
//  NaarsCars
//
//  Lightweight haptic feedback helper
//

import UIKit

enum Haptics {
    static func lightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

