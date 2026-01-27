//
//  ColorTheme.swift
//  NaarsCars
//
//  Brand colors and color theme definitions with dark mode support
//

import SwiftUI
import UIKit

// MARK: - Adaptive Brand Colors

/// Brand colors matching web app design with automatic dark mode support
extension Color {
    
    // MARK: - Primary Brand Colors
    
    /// Primary brand color - Terracotta
    /// Slightly brightened in dark mode for better visibility
    static let naarsPrimary = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "C97A64") // Lighter terracotta for dark mode
        default:
            return UIColor(hex: "B5634B") // Original terracotta
        }
    })
    
    /// Accent color - Warm amber
    /// Slightly brightened in dark mode
    static let naarsAccent = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "E0B88A") // Lighter amber for dark mode
        default:
            return UIColor(hex: "D4A574") // Original amber
        }
    })
    
    // MARK: - Semantic Status Colors
    
    /// Success color - Green
    static let naarsSuccess = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "34D669") // Brighter green for dark mode
        default:
            return UIColor(hex: "22C55E") // Standard green
        }
    })
    
    /// Warning color - Orange/Amber
    static let naarsWarning = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "FBBF24") // Brighter amber for dark mode
        default:
            return UIColor(hex: "F59E0B") // Standard amber
        }
    })
    
    /// Error color - Red
    static let naarsError = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "F87171") // Softer red for dark mode (less harsh)
        default:
            return UIColor(hex: "EF4444") // Standard red
        }
    })
    
    // MARK: - Card Accent Colors
    
    /// Favor card accent color - Teal/Cyan
    static let favorAccent = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "38C9DE") // Brighter teal for dark mode
        default:
            return UIColor(hex: "2DB3C8") // Original teal
        }
    })
    
    /// Ride card accent color - Red
    static let rideAccent = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "F87171") // Softer red for dark mode
        default:
            return UIColor(hex: "EF4444") // Standard red
        }
    })
    
    // MARK: - Background Colors
    
    /// Primary background - main app background
    static let naarsBackground = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "121212") // Material Design dark background
        default:
            return UIColor(hex: "F8F9FA") // Light gray background
        }
    })
    
    /// Secondary background - for grouped content
    static let naarsBackgroundSecondary = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "1E1E1E") // Slightly lighter dark
        default:
            return UIColor(hex: "FFFFFF") // Pure white
        }
    })
    
    /// Card/Surface background
    static let naarsCardBackground = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "2C2C2C") // Elevated surface in dark mode
        default:
            return UIColor(hex: "FFFFFF") // White card
        }
    })
    
    // MARK: - Text Colors
    
    /// Primary text color
    static let naarsTextPrimary = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "F5F5F5") // Off-white (easier on eyes than pure white)
        default:
            return UIColor(hex: "1A1A1A") // Near-black
        }
    })
    
    /// Secondary text color - for less prominent text
    static let naarsTextSecondary = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "A0A0A0") // Medium gray
        default:
            return UIColor(hex: "6B7280") // Gray 500
        }
    })
    
    /// Tertiary text color - for hints and placeholders
    static let naarsTextTertiary = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "707070") // Darker gray
        default:
            return UIColor(hex: "9CA3AF") // Gray 400
        }
    })
    
    // MARK: - Border & Divider Colors
    
    /// Divider/separator color
    static let naarsDivider = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "3A3A3A") // Subtle dark divider
        default:
            return UIColor(hex: "E5E7EB") // Light gray divider
        }
    })
    
    /// Border color for inputs and cards
    static let naarsBorder = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "404040") // Dark mode border
        default:
            return UIColor(hex: "D1D5DB") // Light gray border
        }
    })
    
    // MARK: - Interactive Colors
    
    /// Button disabled state
    static let naarsDisabled = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "4A4A4A") // Dark disabled
        default:
            return UIColor(hex: "D1D5DB") // Light disabled
        }
    })
    
    /// Overlay/scrim color for modals
    static let naarsOverlay = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.black.withAlphaComponent(0.7)
        default:
            return UIColor.black.withAlphaComponent(0.5)
        }
    })
}

// MARK: - UIColor Hex Extension

extension UIColor {
    /// Initialize a UIColor from a hex string
    /// - Parameter hex: Hex color string (e.g., "B5634B" or "#B5634B")
    convenience init(hex: String) {
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
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}

// MARK: - Color Hex Extension (kept for compatibility)extension Color {
    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex color string (e.g., "B5634B" or "#B5634B")
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}