//
//  EmojiDetection.swift
//  NaarsCars
//
//  Detects emoji-only messages for enlarged emoji display (iMessage parity).
//

import Foundation

extension Character {
    /// Returns true if this character renders as an emoji glyph.
    /// Handles ZWJ sequences (family emoji), skin tone modifiers, and keycap sequences.
    ///
    /// Note: `Unicode.Scalar.Properties.isEmoji` is unreliable because it returns
    /// `true` for digits (0-9) and `#`. We use `isEmojiPresentation` as the primary
    /// check and fall back to multi-scalar heuristics for ZWJ sequences.
    var isActualEmoji: Bool {
        // A character with emoji presentation selector always renders as emoji
        if unicodeScalars.first?.properties.isEmojiPresentation == true {
            return true
        }
        // Multi-scalar sequences (ZWJ, skin tones, keycaps) are emoji
        // if the base scalar has the emoji property
        if unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji == true {
            return true
        }
        return false
    }
}

/// Checks whether a message consists of only emoji characters (1-3).
/// Returns a tuple with a boolean flag and the emoji count.
func isEmojiOnlyMessage(_ text: String) -> (isEmojiOnly: Bool, count: Int) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (false, 0) }
    let characters = Array(trimmed)
    guard characters.allSatisfy(\.isActualEmoji) else { return (false, 0) }
    let count = characters.count
    return (count >= 1 && count <= 3) ? (true, count) : (false, 0)
}
