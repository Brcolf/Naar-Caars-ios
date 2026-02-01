//
//  ReplyContextBuilder.swift
//  NaarsCars
//
//  Utility for enriching messages with reply context
//

import Foundation

enum ReplyContextBuilder {
    static func applyReplyContexts(
        messages: [Message],
        profilesById: [UUID: Profile]
    ) -> [Message] {
        guard !messages.isEmpty else { return messages }

        let messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        var enriched = messages

        for index in enriched.indices {
            guard enriched[index].replyToMessage == nil,
                  let replyToId = enriched[index].replyToId,
                  let parent = messagesById[replyToId] else { continue }

            let senderName = parent.sender?.name ?? profilesById[parent.fromId]?.name ?? "Unknown"
            enriched[index].replyToMessage = ReplyContext(
                id: parent.id,
                text: parent.text,
                senderName: senderName,
                senderId: parent.fromId,
                imageUrl: parent.imageUrl
            )
        }

        return enriched
    }
}

