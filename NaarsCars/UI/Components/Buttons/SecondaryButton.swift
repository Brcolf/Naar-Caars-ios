//
//  SecondaryButton.swift
//  NaarsCars
//
//  Secondary action button
//

import SwiftUI

/// Secondary action button with outlined style
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            Text(title)
                .font(.naarsHeadline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.clear)
                .foregroundColor(isDisabled ? Color.naarsDisabled : Color.naarsPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isDisabled ? Color.naarsDisabled : Color.naarsPrimary, lineWidth: 2)
                )
                .cornerRadius(10)
        }
        .buttonStyle(.scale)
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: 20) {
        SecondaryButton(title: "Cancel", action: {})
        SecondaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}

