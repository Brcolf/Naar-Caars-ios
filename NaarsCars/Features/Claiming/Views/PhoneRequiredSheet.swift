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
    @Binding var showProfileScreen: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.naarsPrimary)
                
                Text("claiming_phone_required_title".localized)
                    .font(.naarsTitle2)
                    .fontWeight(.semibold)
                
                Text("claiming_phone_required_message".localized)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Privacy notice
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("claiming_phone_required_privacy".localized)
                }
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.naarsCardBackground)
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    PrimaryButton(title: "claiming_phone_required_add".localized) {
                        dismiss()
                        showProfileScreen = true
                    }
                    
                    SecondaryButton(title: "common_not_now".localized) {
                        dismiss()
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("claiming_phone_required_nav_title".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    PhoneRequiredSheet(showProfileScreen: .constant(false))
}





