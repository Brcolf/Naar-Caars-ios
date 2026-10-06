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
                
                // States the requirement only. The older sentence ended "so the poster can
                // coordinate with you", which the notice below contradicts: no member sees the number.
                Text("claiming_phone_required_message_plain".localized)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Privacy notice
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    // The same sentence Edit Profile shows. The previous one said the number
                    // would be visible to other members, which no screen in the app does.
                    Text("profile_phone_privacy_notice".localized)
                }
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.naarsCardBackground)
                .cornerRadius(Constants.Radius.sm)
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





