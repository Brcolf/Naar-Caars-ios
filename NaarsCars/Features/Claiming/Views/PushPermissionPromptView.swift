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
            
            Text("Stay Connected")
                .font(.naarsTitle2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                BenefitRow(
                    icon: "message.fill",
                    title: "New Messages",
                    description: "Get notified when someone sends you a message"
                )
                
                BenefitRow(
                    icon: "checkmark.circle.fill",
                    title: "Request Updates",
                    description: "Know immediately when someone claims your request"
                )
                
                BenefitRow(
                    icon: "bell.fill",
                    title: "Important Alerts",
                    description: "Receive community announcements and updates"
                )
            }
            .padding(.horizontal)
            
            Text("You can change this later in Settings")
                .font(.naarsCaption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                PrimaryButton(title: "Enable Notifications") {
                    onAllow()
                    dismiss()
                }
                
                SecondaryButton(title: "Not Now") {
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
                .font(.title3)
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


