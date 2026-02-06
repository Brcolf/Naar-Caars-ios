//
//  PushPermissionPromptView.swift
//  NaarsCars
//
//  Custom prompt for push notification permission
//

import SwiftUI

/// Custom prompt explaining benefits of push notifications
struct PushPermissionPromptView: View {
    let onAllow: () -> Void
    let onNotNow: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundColor(.naarsPrimary)
            
            Text("claiming_push_stay_connected".localized)
                .font(.naarsTitle2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                BenefitRow(
                    icon: "message.fill",
                    title: "claiming_push_new_messages".localized,
                    description: "claiming_push_new_messages_desc".localized
                )
                
                BenefitRow(
                    icon: "checkmark.circle.fill",
                    title: "claiming_push_request_updates".localized,
                    description: "claiming_push_request_updates_desc".localized
                )
                
                BenefitRow(
                    icon: "bell.fill",
                    title: "claiming_push_important_alerts".localized,
                    description: "claiming_push_important_alerts_desc".localized
                )
            }
            .padding(.horizontal)
            
            Text("claiming_push_change_later".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                PrimaryButton(title: "claiming_push_enable".localized) {
                    onAllow()
                    dismiss()
                }
                
                SecondaryButton(title: "common_not_now".localized) {
                    onNotNow()
                    dismiss()
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

/// Row component for benefit list
private struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.naarsTitle3)
                .foregroundColor(.naarsPrimary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.naarsHeadline)
                
                Text(description)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    PushPermissionPromptView(
        onAllow: {},
        onNotNow: {}
    )
}



