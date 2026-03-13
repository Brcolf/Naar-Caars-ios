//
//  FrozenConversationBanner.swift
//  NaarsCars
//
//  Read-only banner shown when user has left a conversation
//

import SwiftUI

/// Non-interactive banner replacing the input bar when the user has left a conversation.
struct FrozenConversationBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("messaging_left_conversation".localized)
                .font(.naarsFootnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.naarsCardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("messaging_left_conversation".localized)
    }
}
