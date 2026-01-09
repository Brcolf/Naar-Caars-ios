//
//  ColorTheme.swift
//  NaarsCars
//
//  Brand colors and color theme definitions
//

import SwiftUI

/// Brand colors matching web app design
extension Color {
    /// Primary brand color - Terracotta
    static let naarsPrimary = Color(hex: "B5634B")
    
    /// Accent color - Warm amber
    static let naarsAccent = Color(hex: "D4A574")
    
    /// Success color - Green
    static let naarsSuccess = Color(hex: "22C55E")
    
    /// Warning color - Orange
    static let naarsWarning = Color(hex: "F59E0B")
    
    /// Error color - Red
    static let naarsError = Color(hex: "EF4444")
    
    /// Favor card accent color - Teal/Cyan (complementary to red for rides)
    static let favorAccent = Color(hex: "2DB3C8") // Teal/cyan
    
    /// Ride card accent color - Red
    static let rideAccent = Color(hex: "EF4444") // Red
}

/// Color extension for hex color initialization
extension Color {
    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex color string (e.g., "B5634B" or "#B5634B")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

