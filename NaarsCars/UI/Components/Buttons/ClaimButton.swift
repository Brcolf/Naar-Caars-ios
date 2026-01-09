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

/// Reusable claim button component
struct ClaimButton: View {
    let state: ClaimButtonState
    let action: () -> Void
    var isLoading: Bool = false
    
    var body: some View {
        Button(action: action) {
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




