//
//  UnclaimSheet.swift
//  NaarsCars
//
//  Confirmation sheet for unclaiming a request
//

import SwiftUI

/// Confirmation sheet for unclaiming a request
struct UnclaimSheet: View {
    let requestType: String
    let requestTitle: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsWarning)
                
                Text("Unclaim This \(requestType.capitalized)?")
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("You're about to unclaim:")
                    .foregroundColor(.secondary)
                
                Text(requestTitle)
                    .font(.naarsHeadline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("The request will return to open status and the poster will be notified.")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "Yes, Unclaim") {
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
            .navigationTitle("Unclaim Request")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    UnclaimSheet(
        requestType: "ride",
        requestTitle: "Ride to Airport",
        onConfirm: {}
    )
}





