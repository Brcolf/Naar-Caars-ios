//
//  CompleteSheet.swift
//  NaarsCars
//
//  Confirmation sheet for completing a request
//

import SwiftUI

/// Confirmation sheet for completing a request
struct CompleteSheet: View {
    let requestType: String
    let requestTitle: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsSuccess)
                
                Text("Mark as Completed?")
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("You're marking this as complete:")
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("After marking complete, you'll be prompted to leave a review for your helper.")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "Yes, Mark Complete") {
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
            .navigationTitle("Complete Request")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CompleteSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: {}
    )
}




