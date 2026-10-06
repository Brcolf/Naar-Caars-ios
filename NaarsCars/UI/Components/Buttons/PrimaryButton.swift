//
//  PrimaryButton.swift
//  NaarsCars
//
//  Primary action button with loading state support
//

import SwiftUI

/// Primary action button with loading state
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            HStack(spacing: Constants.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(.naarsHeadline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDisabled && !isLoading ? Color.naarsDisabled : Color.naarsPrimary)
            .foregroundColor(isDisabled && !isLoading ? Color.naarsDisabledContent : .white)
            .opacity(isLoading ? 0.7 : 1)
            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous))
        }
        .buttonStyle(.scale)
        .disabled(isDisabled || isLoading)
    }
}

#Preview {
    VStack(spacing: 20) {
        PrimaryButton(title: "Sign In", action: {})
        PrimaryButton(title: "Loading...", action: {}, isLoading: true)
        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
    }
    .padding()
}

