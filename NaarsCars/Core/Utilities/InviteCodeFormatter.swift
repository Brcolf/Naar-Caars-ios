//
//  InviteCodeFormatter.swift
//  NaarsCars
//
//  Shared formatting utilities for invite codes and share messages
//

import Foundation

/// Utilities for formatting invite codes and generating share messages
/// Used by InvitationWorkflowView, AdminInviteView, and InviteCodeRow
enum InviteCodeFormatter {

    /// Format an invite code with visual separators for readability
    /// - Parameter code: The raw invite code string
    /// - Returns: Formatted code (e.g. "NC7X · 9K2A · BQ" for 10-char codes)
    ///
    /// Format rules based on code length:
    /// - 10 chars (NC + 8): "NC7X · 9K2A · BQ" (groups of 4, 4, 2)
    /// - 8 chars (NC + 6 legacy): "NC7X · 9K2A" (groups of 4, 4)
    /// - Other: returns code as-is
    static func formatCode(_ code: String) -> String {
        let chars = Array(code)
        if code.count == 10 {
            return "\(String(chars[0...3])) · \(String(chars[4...7])) · \(String(chars[8...9]))"
        } else if code.count == 8 {
            return "\(String(chars[0...3])) · \(String(chars[4...7]))"
        }
        return code
    }

    /// Generate a share message for a regular (single-use) invite code
    /// - Parameter code: The raw invite code
    /// - Returns: Formatted share message with app store link and invite code
    static func generateShareMessage(_ code: String) -> String {
        let appStoreLink = Constants.URLs.appStore
        return "invite_share_message_regular".localized(with: appStoreLink, code)
    }

    /// Generate a share message for a bulk invite code
    /// - Parameter code: The raw invite code
    /// - Returns: Formatted share message with app store link, invite code, and bulk-specific note
    static func generateBulkShareMessage(_ code: String) -> String {
        let appStoreLink = Constants.URLs.appStore
        return "invite_share_message_bulk".localized(with: appStoreLink, code)
    }
}
