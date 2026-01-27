//
//  View+Extensions.swift
//  NaarsCars
//
//  SwiftUI view extensions for common modifiers
//

import SwiftUI

extension View {
    /// Apply card style with background, corner radius, and shadow
    /// Automatically adapts to light/dark mode
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.naarsCardBackground)
            .cornerRadius(12)
            .shadow(color: Color.primary.opacity(0.08), radius: 4, x: 0, y: 2)
    }
    
    /// Apply section header style
    func sectionHeaderStyle() -> some View {
        self
            .font(.naarsHeadline)
            .foregroundColor(.naarsTextPrimary)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
}

// MARK: - Bundle Extension

extension Bundle {
    /// App version string (e.g., "1.0.0")
    var appVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    /// Build number string
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    /// Full version string (e.g., "1.0.0 (42)")
    var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }
}