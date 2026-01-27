//
//  ClaimButton.swift
//  NaarsCars
//
//  Reusable claim button component
//

import SwiftUI
import UIKit

/// Claim button states
enum ClaimButtonState {
    case canClaim
    case claimedByMe
    case claimedByOther
    case completed
    case isPoster
}

/// Reusable claim button component
struct ClaimButton: View {
    let state: ClaimButtonState
    let action: () -> Void
    var isLoading: Bool = false
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            action()
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                
                Text(buttonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonColor)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(isLoading || state == .claimedByOther || state == .completed || state == .isPoster)
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
    
    private var buttonColor: Color {
        switch state {
        case .canClaim:
            return .naarsPrimary
        case .claimedByMe:
            return .naarsWarning
        case .claimedByOther:
            return .gray
        case .completed:
            return .gray
        case .isPoster:
            return .gray
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





