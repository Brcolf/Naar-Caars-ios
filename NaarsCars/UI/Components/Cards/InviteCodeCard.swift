//
//  InviteCodeCard.swift
//  NaarsCars
//
//  Invite code card with share and copy actions
//

import SwiftUI

/// Card view for displaying an invite code with actions
struct InviteCodeCard: View {
    let code: InviteCode
    
    var body: some View {
        HStack {
            // Code Display
            VStack(alignment: .leading, spacing: 4) {
                Text(formatCode(code.code))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                
                Text("invite_created_ago".localized(with: code.createdAt.timeAgo))
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Badge
            if code.isUsed {
                Text("invite_status_used".localized)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.secondary)
                    .cornerRadius(Constants.Radius.sm)
            } else {
                Text("invite_status_available".localized)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.naarsSuccess)
                    .cornerRadius(Constants.Radius.sm)
            }
            
            // Actions Menu
            Menu {
                Button {
                    UIPasteboard.general.string = code.code
                } label: {
                    Label("common_copy".localized, systemImage: "doc.on.doc")
                }
                
                ShareLink(item: code.code) {
                    Label("common_share".localized, systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.card)
        .cardShadow()
    }
    
    private func formatCode(_ code: String) -> String {
        InviteCodeFormatter.formatCode(code)
    }
}

#Preview {
    VStack(spacing: 12) {
        InviteCodeCard(
            code: InviteCode(
                code: "NC7X9K2ABQ",
                createdBy: UUID()
            )
        )
        
        InviteCodeCard(
            code: InviteCode(
                code: "ABCD1234",
                createdBy: UUID(),
                usedBy: UUID(),
                usedAt: Date()
            )
        )
    }
    .padding()
}





