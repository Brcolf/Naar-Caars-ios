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
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.clear)
                .foregroundColor(isDisabled ? Color.gray : Color.naarsPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isDisabled ? Color.gray : Color.naarsPrimary, lineWidth: 2)
                )
                .cornerRadius(10)
        }
        .disabled(isDisabled)
    }
}

#Preview {
    VStack(spacing: 20) {
        SecondaryButton(title: "Cancel", action: {})
        SecondaryButton(title: "Disabled", isDisabled: true, action: {})
    }
    .padding()
}

