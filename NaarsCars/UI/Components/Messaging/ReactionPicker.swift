//
//  ReactionPicker.swift
//  NaarsCars
//
//  Reaction picker component for messages
//

import SwiftUI

/// Reaction picker overlay (displays on long press)
struct ReactionPicker: View {
    let onReactionSelected: (String) -> Void
    let onDismiss: () -> Void
    
    private let reactions = ["👍", "👎", "❤️", "😂", "‼️", "HaHa"]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(reactions, id: \.self) { reaction in
                Button(action: {
                    onReactionSelected(reaction)
                    onDismiss()
                }) {
                    Text(reaction)
                        .font(.system(size: 32))
                        .padding(8)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemGray6))
                .shadow(radius: 8)
        )
    }
}

#Preview {
    ReactionPicker(
        onReactionSelected: { reaction in
            print("Selected: \(reaction)")
        },
        onDismiss: {}
    )
    .padding()
}

