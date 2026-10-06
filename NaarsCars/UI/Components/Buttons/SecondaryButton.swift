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
    /// Draws the button in `naarsError` for an action that removes something
    var isDestructive: Bool = false

    private var contentColor: Color {
        if isDisabled { return .naarsDisabledContent }
        return isDestructive ? .naarsError : .naarsPrimary
    }
    
    var body: some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            Text(title)
                .font(.naarsHeadline)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(contentColor)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous)
                        .strokeBorder(contentColor, lineWidth: 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous))
        }
        .buttonStyle(.scale)
        .disabled(isDisabled)
    }
}

extension SecondaryButton {
    /// Trailing-closure form for an action that removes something.
    init(title: String, isDestructive: Bool, action: @escaping () -> Void) {
        self.init(title: title, action: action, isDisabled: false, isDestructive: isDestructive)
    }
}

#Preview {
    VStack(spacing: 20) {
        SecondaryButton(title: "Cancel", action: {})
        SecondaryButton(title: "Delete", isDestructive: true) {}
        SecondaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}

