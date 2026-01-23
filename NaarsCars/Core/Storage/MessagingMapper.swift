//
//  MessagingMapper.swift
//  NaarsCars
//

import Foundation
import Realtime

struct MessagingMapper {
    static func mapToSDConversation(_ conversation: Conversation, participantIds: [UUID] = []) -> SDConversation {
        return SDConversation(
            id: conversation.id,
            title: conversation.title,
            groupImageUrl: conversation.groupImageUrl,
            createdBy: conversation.createdBy,
            isArchived: conversation.isArchived,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            participantIds: participantIds
        )
    }
    
    static func mapToSDMessage(_ message: Message, isPending: Bool = false) -> SDMessage {
        return SDMessage(
            id: message.id,
            conversationId: message.conversationId,
            fromId: message.fromId,
            text: message.text,
            imageUrl: message.imageUrl,
            readBy: message.readBy,
            createdAt: message.createdAt,
            messageType: message.messageType?.rawValue ?? "text",
            replyToId: message.replyToId,
            audioUrl: message.audioUrl,
            audioDuration: message.audioDuration,
            latitude: message.latitude,
            longitude: message.longitude,
            locationName: message.locationName,
            isPending: isPending
        )
    }
    
    static func mapToMessage(_ sdMessage: SDMessage) -> Message {
        return Message(
            id: sdMessage.id,
            conversationId: sdMessage.conversationId,
            fromId: sdMessage.fromId,
            text: sdMessage.text,
            imageUrl: sdMessage.imageUrl,
            readBy: sdMessage.readBy,
            createdAt: sdMessage.createdAt,
            messageType: MessageType(rawValue: sdMessage.messageType),
            replyToId: sdMessage.replyToId,
            audioUrl: sdMessage.audioUrl,
            audioDuration: sdMessage.audioDuration,
            latitude: sdMessage.latitude,
            longitude: sdMessage.longitude,
            locationName: sdMessage.locationName
        )
    }
    
    static func mapToConversation(_ sdConversation: SDConversation, lastMessage: Message? = nil, unreadCount: Int = 0) -> Conversation {
        return Conversation(
            id: sdConversation.id,
            title: sdConversation.title,
            groupImageUrl: sdConversation.groupImageUrl,
            createdBy: sdConversation.createdBy,
            isArchived: sdConversation.isArchived,
            createdAt: sdConversation.createdAt,
            updatedAt: sdConversation.updatedAt,
            participants: nil, // Participants are handled separately via participantIds
            lastMessage: lastMessage,
            unreadCount: unreadCount
        )
    }

    static func parseMessageFromPayload(_ payload: Any) -> Message? {
        var recordDict: [String: Any]?
        
        if let insertAction = payload as? Realtime.InsertAction {
            recordDict = insertAction.record
        } else if let updateAction = payload as? Realtime.UpdateAction {
            recordDict = updateAction.record
        } else if let dict = payload as? [String: Any] {
            recordDict = dict["record"] as? [String: Any] ?? dict
        }
        
        guard let record = recordDict else { return nil }
        
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let conversationIdString = record["conversation_id"] as? String,
              let convId = UUID(uuidString: conversationIdString),
              let fromIdString = record["from_id"] as? String,
              let fromId = UUID(uuidString: fromIdString),
              let text = record["text"] as? String else {
            return nil
        }
        
        let imageUrl = record["image_url"] as? String
        let replyToId = (record["reply_to_id"] as? String).flatMap(UUID.init)
        let messageType = (record["message_type"] as? String).flatMap(MessageType.init(rawValue:))
        let audioUrl = record["audio_url"] as? String
        let audioDuration = parseDouble(record["audio_duration"])
        let latitude = parseDouble(record["latitude"])
        let longitude = parseDouble(record["longitude"])
        let locationName = record["location_name"] as? String
        
        var readBy: [UUID] = []
        if let readByArray = record["read_by"] as? [String] {
            readBy = readByArray.compactMap { UUID(uuidString: $0) }
        }
        
        var createdAt = Date()
        if let createdAtString = record["created_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAtString) {
                createdAt = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: createdAtString) {
                    createdAt = date
                }
            }
        }
        
        return Message(
            id: id,
            conversationId: convId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            readBy: readBy,
            createdAt: createdAt,
            messageType: messageType,
            replyToId: replyToId,
            audioUrl: audioUrl,
            audioDuration: audioDuration,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let intValue = value as? Int { return Double(intValue) }
        if let stringValue = value as? String { return Double(stringValue) }
        return nil
    }
}

