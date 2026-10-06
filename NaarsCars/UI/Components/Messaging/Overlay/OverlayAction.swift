//
//  OverlayAction.swift
//  NaarsCars
//
//  Actions available in the message interaction overlay
//

import Foundation

/// Actions that can be triggered from the message interaction overlay
enum OverlayAction {
    case react(String)
    case removeReaction
    case reply
    case viewThread(UUID)
    case copy
    case edit
    case unsend
    case deleteForMe
    case report

    /// Stable identifier for accessibility, not user-facing
    var accessibilityName: String {
        switch self {
        case .react: return "react"
        case .removeReaction: return "removeReaction"
        case .reply: return "reply"
        case .viewThread: return "viewThread"
        case .copy: return "copy"
        case .edit: return "edit"
        case .unsend: return "unsend"
        case .deleteForMe: return "deleteForMe"
        case .report: return "report"
        }
    }
}

/// Which rows the long-press overlay (and swipe-to-reply) applies to. Client-side gating only:
/// it stops the app offering actions the row cannot accept.
enum MessageOverlayAvailability {

    /// A system line ("Alex added Sam") or an unsent / moderation-hidden placeholder. These are
    /// not messages the user can react to, reply to, edit, unsend or delete. (Another member's
    /// system line can still be reported, see `canPresentOverlay`.)
    static func isPlaceholder(_ message: Message) -> Bool {
        message.isModerationHidden || message.isUnsent || message.messageType == .system
    }

    /// Still sending or failed: the row exists only on this device, so every server-side
    /// action (reaction, reply, edit, unsend, report) would be refused.
    static func isLocalOnly(_ message: Message) -> Bool {
        message.sendStatus == .sending || message.sendStatus == .failed
    }

    /// Reactions, reply, edit, unsend and report need a real message that reached the server.
    static func allowsServerActions(for message: Message) -> Bool {
        !isPlaceholder(message) && !isLocalOnly(message)
    }

    /// Whether the overlay has anything to offer for this row. An unsent or hidden placeholder
    /// offers nothing; a message still on its way offers only Copy, so it needs text. A system
    /// line offers Report when another member caused it: the line can carry text they typed
    /// (a group name), and reporting has to stay reachable wherever member-written text shows.
    static func canPresentOverlay(for message: Message, isFromCurrentUser: Bool) -> Bool {
        if message.isModerationHidden || message.isUnsent { return false }
        if message.messageType == .system { return !isFromCurrentUser }
        if message.sendStatus == .sending { return !message.text.isEmpty }
        return true
    }

    /// Body of the confirmation shown before Delete for Me. A failed message never reached
    /// anyone, so "other participants will still see it" would be wrong for it.
    static func deleteForMeConfirmationText(for message: Message) -> String {
        message.sendStatus == .failed
            ? "messaging_delete_failed_message_confirmation".localized
            : "messaging_delete_for_me_confirmation".localized
    }
}
