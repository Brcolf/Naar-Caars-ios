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
