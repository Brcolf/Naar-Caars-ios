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
    
    /// Human-readable description for each reaction emoji
    private func reactionDescription(_ reaction: String) -> String {
        switch reaction {
        case "👍": return "thumbs up"
        case "👎": return "thumbs down"
        case "❤️": return "heart"
        case "😂": return "laughing face"
        case "‼️": return "double exclamation mark"
        case "HaHa": return "ha ha"
        default: return reaction
        }
    }
    
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
                        .background(Color.naarsBackgroundSecondary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("React with \(reactionDescription(reaction))")
                .accessibilityHint("Double-tap to add this reaction")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.naarsCardBackground)
                .shadow(radius: 8)
        )
    }
}

#Preview {
    ReactionPicker(
        onReactionSelected: { reaction in
            AppLogger.info("messaging", "Reaction selected: \(reaction)")
        },
        onDismiss: {}
    )
    .padding()
}

