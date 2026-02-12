//
//  MessagingMapper.swift
//  NaarsCars
//

import Foundation

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
            editedAt: message.editedAt,
            deletedAt: message.deletedAt,
            isPending: isPending,
            status: message.sendStatus?.rawValue ?? (isPending ? "sending" : "sent"),
            localAttachmentPath: message.localAttachmentPath
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
            editedAt: sdMessage.editedAt,
            deletedAt: sdMessage.deletedAt,
            audioUrl: sdMessage.audioUrl,
            audioDuration: sdMessage.audioDuration,
            latitude: sdMessage.latitude,
            longitude: sdMessage.longitude,
            locationName: sdMessage.locationName,
            sendStatus: MessageSendStatus(rawValue: sdMessage.status),
            localAttachmentPath: sdMessage.localAttachmentPath,
            syncError: sdMessage.syncError
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

    static func parseMessage(from record: [String: Any]) -> Message? {
        guard let id = parseUUID(record["id"]),
              let convId = parseUUID(record["conversation_id"]),
              let fromId = parseUUID(record["from_id"]),
              let text = parseString(record["text"]) else {
            AppLogger.warning("messaging", "Missing required fields in record: \(Array(record.keys))")
            return nil
        }
        
        let imageUrl = parseString(record["image_url"])
        let replyToId = parseUUID(record["reply_to_id"])
        let messageType = parseString(record["message_type"]).flatMap(MessageType.init(rawValue:))
        let audioUrl = parseString(record["audio_url"])
        let audioDuration = parseDouble(record["audio_duration"])
        let latitude = parseDouble(record["latitude"])
        let longitude = parseDouble(record["longitude"])
        let locationName = parseString(record["location_name"])
        let editedAt = parseDate(record["edited_at"])
        let deletedAt = parseDate(record["deleted_at"])
        
        var readBy: [UUID] = []
        if let readByArray = normalizeValue(record["read_by"]) as? [Any] {
            readBy = readByArray.compactMap { parseUUID($0) }
        }
        
        var createdAt = Date()
        if let createdAtDate = normalizeValue(record["created_at"]) as? Date {
            createdAt = createdAtDate
        } else if let createdAtString = parseString(record["created_at"]) {
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
        } else if let createdAtNumber = normalizeValue(record["created_at"]) as? NSNumber {
            let rawValue = createdAtNumber.doubleValue
            if rawValue > 10_000_000_000 {
                createdAt = Date(timeIntervalSince1970: rawValue / 1000.0)
            } else {
                createdAt = Date(timeIntervalSince1970: rawValue)
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
            editedAt: editedAt,
            deletedAt: deletedAt,
            audioUrl: audioUrl,
            audioDuration: audioDuration,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        let normalized = normalizeValue(value)
        if let dateValue = normalized as? Date { return dateValue }
        if let stringValue = normalized as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: stringValue) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: stringValue) { return date }
        }
        if let numberValue = normalized as? NSNumber {
            let rawValue = numberValue.doubleValue
            if rawValue > 10_000_000_000 {
                return Date(timeIntervalSince1970: rawValue / 1000.0)
            } else {
                return Date(timeIntervalSince1970: rawValue)
            }
        }
        return nil
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        let normalized = normalizeValue(value)
        if let doubleValue = normalized as? Double { return doubleValue }
        if let intValue = normalized as? Int { return Double(intValue) }
        if let stringValue = normalized as? String { return Double(stringValue) }
        if let numberValue = normalized as? NSNumber { return numberValue.doubleValue }
        return nil
    }

    private static func parseString(_ value: Any?) -> String? {
        let normalized = normalizeValue(value)
        if let stringValue = normalized as? String { return stringValue }
        if let substringValue = normalized as? Substring { return String(substringValue) }
        if let nsStringValue = normalized as? NSString { return nsStringValue as String }
        return nil
    }

    private static func parseUUID(_ value: Any?) -> UUID? {
        let normalized = normalizeValue(value)
        if let uuidValue = normalized as? UUID { return uuidValue }
        if let nsuuidValue = normalized as? NSUUID { return nsuuidValue as UUID }
        if let stringValue = normalized as? String { return UUID(uuidString: stringValue) }
        if let nsStringValue = normalized as? NSString { return UUID(uuidString: nsStringValue as String) }
        return nil
    }

    private static func normalizeValue(_ value: Any?) -> Any? {
        RealtimePayloadAdapter.normalizeValue(value)
    }
}

