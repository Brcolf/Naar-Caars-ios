//
//  PhoneRequiredSheet.swift
//  NaarsCars
//
//  Sheet prompting user to add phone number
//

import SwiftUI

/// Sheet prompting user to add phone number before claiming
struct PhoneRequiredSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var navigateToProfile: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsPrimary)
                
                Text("Phone Number Required")
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("To claim requests, you need to add a phone number so the poster can coordinate with you.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Privacy notice
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Your number will be visible to other community members.")
                }
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "Add Phone Number") {
                        dismiss()
                        navigateToProfile = true
                    }
                    
                    SecondaryButton(title: "Not Now") {
                        dismiss()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Phone Required")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    PhoneRequiredSheet(navigateToProfile: .constant(false))
}




