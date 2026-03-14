//
//  ReactionDetailsSheet.swift
//  NaarsCars
//
//  Sheet showing detailed reaction information for a message
//

import SwiftUI

struct ReactionDetailsSheet: View {
    let message: Message
    let reactions: MessageReactions
    let profilesByReaction: [String: [Profile]]
    let onRemoveReaction: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedReactions, id: \.reaction) { reactionData in
                    Section(header: reactionHeader(emoji: reactionData.reaction, count: reactionData.count)) {
                        ForEach(profilesByReaction[reactionData.reaction] ?? [], id: \.id) { profile in
                            HStack(spacing: 12) {
                                AvatarView(
                                    imageUrl: profile.avatarUrl,
                                    name: profile.name,
                                    size: 32
                                )
                                Text(profile.name)
                                    .font(.naarsSubheadline).fontWeight(.medium)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                if let currentUserId = AuthService.shared.currentUserId {
                    let myReactions = reactions.reactions.filter { $0.value.contains(currentUserId) }
                    if !myReactions.isEmpty {
                        Section {
                            ForEach(myReactions.keys.sorted(), id: \.self) { reaction in
                                Button(role: .destructive) {
                                    onRemoveReaction(reaction)
                                } label: {
                                    Text("messaging_remove_reaction".localized(with: reaction))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("messaging_reactions_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("messaging_done".localized) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func reactionHeader(emoji: String, count: Int) -> some View {
        HStack(spacing: 4) {
            if let uiImage = TapbackGlyph.image(for: emoji, pointSize: 18) {
                Image(uiImage: uiImage)
            } else {
                Text(emoji)
            }
            Text("\(count)")
        }
    }

    private var sortedReactions: [(reaction: String, count: Int, userIds: [UUID])] {
        reactions.sortedReactions.sorted {
            if $0.count == $1.count {
                return $0.reaction < $1.reaction
            }
            return $0.count > $1.count
        }
    }
}
