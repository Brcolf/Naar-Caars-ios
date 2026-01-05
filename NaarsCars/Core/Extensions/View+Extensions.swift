//
//  View+Extensions.swift
//  NaarsCars
//
//  SwiftUI view extensions for common modifiers
//

import SwiftUI

extension View {
    /// Apply card style with background, corner radius, and shadow
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    /// Apply section header style
    func sectionHeaderStyle() -> some View {
        self
            .font(.naarsHeadline)
            .foregroundColor(.primary)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
}

