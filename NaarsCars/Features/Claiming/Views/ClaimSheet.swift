//
//  ClaimSheet.swift
//  NaarsCars
//
//  Confirmation sheet for claiming a request
//

import SwiftUI

/// Confirmation sheet for claiming a request
struct ClaimSheet: View {
    let requestType: String
    let requestTitle: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsPrimary)
                
                Text("Claim This \(requestType.capitalized)?")
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("You're volunteering to help with:")
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("A conversation will be created so you can coordinate with the poster.")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "Yes, I Can Help!") {
                        onConfirm()
                        dismiss()
                    }
                    
                    SecondaryButton(title: "Cancel") {
                        dismiss()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Claim Request")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ClaimSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: {}
    )
}




