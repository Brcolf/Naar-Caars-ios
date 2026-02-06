//
//  MessageSeriesHelper.swift
//  NaarsCars
//
//  Shared logic for detecting message series boundaries in chat views
//

import Foundation

/// Utility for determining message grouping ("series") boundaries in chat views
///
/// A "series" is a consecutive run of messages from the same sender within a time window.
/// Messages are grouped into the same series when:
/// - They share the same sender (`fromId`)
/// - They are sent within 5 minutes of each other
///
/// Used by ConversationDetailView and MessageThreadView to control bubble styling
/// (e.g., avatar display, tail visibility, spacing).
enum MessageSeriesHelper {

    /// The maximum time interval (in seconds) between two messages
    /// for them to be considered part of the same series
    static let seriesTimeThreshold: TimeInterval = 300 // 5 minutes

    /// Check if a message is the first in a consecutive series from the same sender
    /// - Parameters:
    ///   - messages: The array of messages
    ///   - index: The index of the message to check
    /// - Returns: `true` if this message starts a new series
    static func isFirstInSeries(messages: [Message], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let currentMessage = messages[index]
        let previousMessage = messages[index - 1]

        // Different sender = first in new series
        if currentMessage.fromId != previousMessage.fromId {
            return true
        }

        // More than threshold apart = new series
        let timeDiff = currentMessage.createdAt.timeIntervalSince(previousMessage.createdAt)
        return timeDiff > seriesTimeThreshold
    }

    /// Check if a message is the last in a consecutive series from the same sender
    /// - Parameters:
    ///   - messages: The array of messages
    ///   - index: The index of the message to check
    /// - Returns: `true` if this message ends the current series
    static func isLastInSeries(messages: [Message], at index: Int) -> Bool {
        guard index < messages.count - 1 else { return true }
        let currentMessage = messages[index]
        let nextMessage = messages[index + 1]

        // Different sender = last in current series
        if currentMessage.fromId != nextMessage.fromId {
            return true
        }

        // More than threshold apart = end of series
        let timeDiff = nextMessage.createdAt.timeIntervalSince(currentMessage.createdAt)
        return timeDiff > seriesTimeThreshold
    }
}
