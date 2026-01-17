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
                
                Text("Created \(code.createdAt.timeAgo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Badge
            if code.isUsed {
                Text("Used")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.secondary)
                    .cornerRadius(8)
            } else {
                Text("Available")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(8)
            }
            
            // Actions Menu
            Menu {
                Button {
                    UIPasteboard.general.string = code.code
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                ShareLink(item: code.code) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func formatCode(_ code: String) -> String {
        // Format as NC7X · 9K2A · BQ (groups of 4)
        var formatted = ""
        for (index, char) in code.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted += " · "
            }
            formatted.append(char)
        }
        return formatted
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





