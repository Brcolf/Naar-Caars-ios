//
//  ClaimButton.swift
//  NaarsCars
//
//  Reusable claim button component
//

import SwiftUI

/// Claim button states
enum ClaimButtonState {
    case canClaim
    case claimedByMe
    case claimedByOther
    case completed
    case isPoster
}

/// Reusable claim button component.
///
/// One capsule, three looks: a filled primary action when the request can be claimed, an
/// outlined secondary action to give it back, and a flat neutral label for the states where
/// there is nothing to do.
struct ClaimButton: View {
    let state: ClaimButtonState
    let action: () -> Void
    var isLoading: Bool = false

    private var isInteractive: Bool {
        state == .canClaim || state == .claimedByMe
    }
    
    var body: some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            HStack(spacing: Constants.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: contentColor))
                        .scaleEffect(0.8)
                }
                
                Text(buttonTitle)
                    .font(.naarsHeadline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(fillColor)
            .foregroundColor(contentColor)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous)
                    .strokeBorder(state == .claimedByMe ? Color.naarsPrimary : Color.clear, lineWidth: 1.5)
            )
            .opacity(isLoading ? 0.7 : 1)
            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Constants.Radius.button, style: .continuous))
        }
        .buttonStyle(.scale)
        .disabled(isLoading || !isInteractive)
        .accessibilityIdentifier("claim.button.\(accessibilityState)")
    }
    
    private var buttonTitle: String {
        switch state {
        case .canClaim:
            return "I Can Help!"
        case .claimedByMe:
            return "Unclaim"
        case .claimedByOther:
            return "Claimed by Someone Else"
        case .completed:
            return "Completed"
        case .isPoster:
            return "You Posted This"
        }
    }
    
    private var fillColor: Color {
        switch state {
        case .canClaim:
            return .naarsPrimary
        case .claimedByMe:
            return .clear
        case .claimedByOther, .completed, .isPoster:
            return .naarsDisabled
        }
    }

    private var contentColor: Color {
        switch state {
        case .canClaim:
            return .white
        case .claimedByMe:
            return .naarsPrimary
        case .claimedByOther, .completed, .isPoster:
            return .secondary
        }
    }
    
    private var accessibilityState: String {
        switch state {
        case .canClaim:
            return "canClaim"
        case .claimedByMe:
            return "claimedByMe"
        case .claimedByOther:
            return "claimedByOther"
        case .completed:
            return "completed"
        case .isPoster:
            return "isPoster"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ClaimButton(state: .canClaim, action: {})
        ClaimButton(state: .claimedByMe, action: {})
        ClaimButton(state: .claimedByOther, action: {})
        ClaimButton(state: .completed, action: {})
        ClaimButton(state: .isPoster, action: {})
        ClaimButton(state: .canClaim, action: {}, isLoading: true)
    }
    .padding()
}





