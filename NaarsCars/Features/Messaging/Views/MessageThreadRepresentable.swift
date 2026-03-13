//
//  MessageThreadRepresentable.swift
//  NaarsCars
//
//  SwiftUI wrapper for MessageThreadViewController
//

import SwiftUI

struct MessageThreadRepresentable: UIViewControllerRepresentable {
    let conversationId: UUID
    let parentMessageId: UUID
    let conversationViewModel: ConversationDetailViewModel
    let isGroup: Bool
    let totalParticipants: Int
    let participantProfiles: [Profile]
    var hasLeftConversation: Bool = false

    func makeUIViewController(context: Context) -> MessageThreadViewController {
        MessageThreadViewController(
            conversationId: conversationId,
            parentMessageId: parentMessageId,
            conversationViewModel: conversationViewModel,
            isGroup: isGroup,
            totalParticipants: totalParticipants,
            participantProfiles: participantProfiles,
            hasLeftConversation: hasLeftConversation
        )
    }

    func updateUIViewController(_ vc: MessageThreadViewController, context: Context) {}
}
