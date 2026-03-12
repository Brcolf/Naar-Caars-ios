//
//  MessageListItem.swift
//  NaarsCars
//
//  Snapshot item type for the diffable data source in MessagesCollectionView.
//  Defined in its own file to avoid @MainActor inference from UIViewRepresentable.
//

import Foundation

/// Snapshot item identifier for the diffable data source.
///
/// Wraps a `String` to stay fully `Sendable` and avoid `@MainActor` isolation issues.
/// Messages are encoded as their UUID string; date separators are prefixed with `"date:"`.
struct MessageListItem: Hashable, Sendable {
    let rawValue: String

    var isDateSeparator: Bool { rawValue.hasPrefix("date:") }

    var messageId: UUID? {
        isDateSeparator ? nil : UUID(uuidString: rawValue)
    }

    var dateSeparatorKey: TimeInterval? {
        guard isDateSeparator else { return nil }
        return Double(rawValue.dropFirst(5))
    }

    static func message(_ id: UUID) -> MessageListItem {
        MessageListItem(rawValue: id.uuidString)
    }

    static func dateSeparator(_ dayKey: TimeInterval) -> MessageListItem {
        MessageListItem(rawValue: "date:\(dayKey)")
    }
}

/// Data passed from SwiftUI to configure each message cell
struct MessageCellConfiguration: Hashable, Sendable {
    let messageId: UUID
    let isFirstInSeries: Bool
    let isLastInSeries: Bool
    let showDateSeparator: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messageId == rhs.messageId
    }
}
