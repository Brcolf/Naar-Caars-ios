//
//  ReactionPicker.swift
//  NaarsCars
//
//  Reaction picker with quick-access row and expandable extended grid
//

import SwiftUI

/// Reaction picker with iMessage-style quick-access row and expandable extras
struct ReactionPicker: View {
    let currentUserReaction: String?
    let onReactionSelected: (String) -> Void
    let onDismiss: () -> Void

    @State private var showExtended = false

    private let quickReactions = ["❤️", "👍", "👎", "😂", "‼️", "❓"]
    private let extendedReactions = ["🔥", "👏", "😢", "😮", "🙏", "💯", "🎉", "😍", "🤔", "💀", "😱", "👀", "✅", "❌", "🙌"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 8) {
            // Quick-access row
            HStack(spacing: 10) {
                ForEach(quickReactions, id: \.self) { reaction in
                    reactionButton(reaction)
                }

                // Expand button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showExtended.toggle()
                    }
                } label: {
                    Image(systemName: showExtended ? "chevron.up" : "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel(showExtended ? "Show fewer reactions" : "Show more reactions")
            }

            // Extended grid
            if showExtended {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(extendedReactions, id: \.self) { reaction in
                        reactionButton(reaction)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }

    private func reactionButton(_ reaction: String) -> some View {
        let isSelected = currentUserReaction == reaction
        return Button {
            HapticManager.selectionChanged()
            onReactionSelected(reaction)
            onDismiss()
        } label: {
            Text(reaction)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.naarsPrimary.opacity(0.2) : Color.clear)
                .clipShape(Circle())
                .scaleEffect(isSelected ? 1.15 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("React with \(reaction)")
    }
}

#Preview {
    ReactionPicker(
        currentUserReaction: "❤️",
        onReactionSelected: { _ in },
        onDismiss: {}
    )
    .padding()
}
