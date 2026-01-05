//
//  PendingApprovalView.swift
//  NaarsCars
//
//  View shown when user is waiting for admin approval
//

import SwiftUI

/// View displayed when user account is pending admin approval
struct PendingApprovalView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hourglass")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Waiting for Approval")
                .font(.title)
                .foregroundColor(.primary)
            
            Text("Your account is pending approval from an administrator. You'll be notified once your account has been approved.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
    }
}

#Preview {
    PendingApprovalView()
}

