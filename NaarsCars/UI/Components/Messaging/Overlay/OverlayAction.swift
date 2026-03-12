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
    case copy
    case edit
    case unsend
    case deleteForMe
    case report
}
