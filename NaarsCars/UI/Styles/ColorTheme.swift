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
            return UIColor(hex: "A35944") // Terracotta, 5.2:1 against white (was B5634B, 4.3:1)
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
            return UIColor(hex: "137A39") // 5.4:1 on white (was 22C55E, 2.3:1)
        }
    })
    
    /// Warning color - Orange/Amber
    static let naarsWarning = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "FBBF24") // Brighter amber for dark mode
        default:
            return UIColor(hex: "A35200") // 5.6:1 on white (was F59E0B, 2.2:1)
        }
    })
    
    /// Error and destructive color - Red. The only red in the app besides `naarsBadge`.
    static let naarsError = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "F87171") // Softer red for dark mode (less harsh)
        default:
            return UIColor(hex: "C62828") // 5.6:1 on white (was EF4444, 3.8:1)
        }
    })

    /// Unread-count badge fill. Fixed in both appearances so white text stays at 5:1.
    static let naarsBadge = Color(UIColor(hex: "D32F2F"))

    /// Fill of a muted (silenced) count badge. A fixed gray for the same reason as `naarsBadge`:
    /// white text stays at 5:1 in both appearances (`Color.secondary` gave 3.4:1 and 3.3:1).
    static let naarsBadgeMuted = Color(UIColor(hex: "6E6E73"))

    /// Rating stars. Dark enough in light mode to read as a shape on white (3.5:1).
    static let naarsRating = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "FBBF24")
        default:
            return UIColor(hex: "C2780A")
        }
    })
    
    // MARK: - Card Accent Colors
    
    /// Favor accent color - Teal. Used for favor cards, detail headers and map pins.
    static let favorAccent = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "2DD4BF")
        default:
            return UIColor(hex: "0F766E") // 5.5:1 on white (was 2DB3C8, 2.5:1)
        }
    })
    
    /// Ride accent color - Blue. Used for ride cards, detail headers and map pins.
    /// Was the same red as `naarsError`, which made every ride read as a failure.
    static let rideAccent = Color(UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "6EA8FF")
        default:
            return UIColor(hex: "1D5FD6") // 5.7:1 on white
        }
    })
    
    // MARK: - Background Colors
    
    /// Primary background - main app background
    // System grouped background: #F2F2F7 light / #000000 dark. The former custom #121212 sat
    // between pure-black system surfaces (Profile, pickers) and #1E1E1E cards, so dark mode
    // showed three different blacks on one screen.
    static let naarsBackground = Color(UIColor.systemGroupedBackground)
    
    /// Secondary background - for grouped content
    // Secondary grouped background: #FFFFFF light / #1C1C1E dark (matches system cards).
    static let naarsBackgroundSecondary = Color(UIColor.secondarySystemGroupedBackground)
    
    /// Card/Surface background
    // Same surface as naarsBackgroundSecondary. The two used to differ only in dark mode
    // (#2C2C2C against #1C1C1E), so cards on one screen showed two grays.
    static let naarsCardBackground = Color(UIColor.secondarySystemGroupedBackground)

    /// Fill for a block nested inside a card (placeholders, inset rows, quoted content):
    /// #F2F2F7 light / #2C2C2E dark.
    static let naarsInsetBackground = Color(UIColor.tertiarySystemGroupedBackground)
    
    // MARK: - Text Colors
    
    // Text tokens are the system label colors. Views use `.primary` / `.secondary` in most
    // places; these resolve to the same values so both spellings draw the same gray.

    /// Primary text color (`.primary`)
    static let naarsTextPrimary = Color(UIColor.label)
    
    /// Secondary text color - for less prominent text (`.secondary`)
    static let naarsTextSecondary = Color(UIColor.secondaryLabel)
    
    /// Tertiary text color - placeholders and disabled content only; too faint for reading text
    static let naarsTextTertiary = Color(UIColor.tertiaryLabel)
    
    // MARK: - Border & Divider Colors
    
    /// Divider/separator color (matches `Divider()`)
    static let naarsDivider = Color(UIColor.separator)
    
    /// Border color for inputs and cards
    static let naarsBorder = Color(UIColor.separator)
    
    // MARK: - Interactive Colors
    
    /// Fill of a disabled or non-interactive control. Pair with `naarsDisabledContent`.
    static let naarsDisabled = Color(UIColor.systemGray5)

    /// Label and stroke on a disabled control
    static let naarsDisabledContent = Color(UIColor.tertiaryLabel)
    
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

// MARK: - UIColor Brand Colors

extension UIColor {

    // MARK: - Primary Brand Colors

    /// Primary brand color - Terracotta (UIKit equivalent of Color.naarsPrimary)
    static let naarsPrimary = UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hex: "C97A64") // Lighter terracotta for dark mode
        default:
            return UIColor(hex: "A35944") // Terracotta, 5.2:1 against white (was B5634B, 4.3:1)
        }
    }

    // MARK: - Background Colors

    /// Secondary background - for grouped content (UIKit equivalent of Color.naarsBackgroundSecondary)
    // Mirrors Color.naarsBackgroundSecondary (system secondary grouped background).
    static let naarsBackgroundSecondary = UIColor.secondarySystemGroupedBackground

    /// Card/Surface background (UIKit equivalent of Color.naarsCardBackground)
    static let naarsCardBackground = UIColor.secondarySystemGroupedBackground

    static let naarsAccent = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(hex: "E0B88A") : UIColor(hex: "D4A574")
    }
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

// MARK: - Color Hex Extension (kept for compatibility)

extension Color {
    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex color string (e.g., "B5634B" or "#B5634B")
    init(hex: String) {
        self.init(UIColor(hex: hex))
    }
}