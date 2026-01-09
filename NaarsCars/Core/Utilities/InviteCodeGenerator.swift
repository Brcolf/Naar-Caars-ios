//
//  InviteCodeGenerator.swift
//  NaarsCars
//
//  Secure invite code generation utility
//

import Foundation

/// Utility for generating secure invite codes
/// Uses character set excluding confusing characters (0/O, 1/I/L)
/// Format: "NC" + 8 random characters (10 total)
struct InviteCodeGenerator {
    /// Character set excluding confusing characters
    /// No 0/O, 1/I/L to prevent user confusion
    private static let charset = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    
    /// Generate a new invite code
    /// Format: "NC" + 8 random characters (10 total)
    /// - Returns: Generated invite code string
    static func generate() -> String {
        let prefix = "NC"
        var code = prefix
        
        // Generate 8 random characters
        for _ in 0..<8 {
            let randomIndex = Int.random(in: 0..<charset.count)
            let character = charset[charset.index(charset.startIndex, offsetBy: randomIndex)]
            code.append(character)
        }
        
        return code
    }
    
    /// Validate invite code format
    /// Accepts both 6-char (legacy NC + 6) and 8-char (new NC + 8) codes
    /// - Parameter code: Code to validate
    /// - Returns: True if format is valid
    static func isValidFormat(_ code: String) -> Bool {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        
        // Check if starts with "NC"
        guard normalized.hasPrefix("NC") else {
            return false
        }
        
        // Check length: NC + 6 (legacy) or NC + 8 (new)
        let suffix = String(normalized.dropFirst(2))
        return suffix.count == 6 || suffix.count == 8
    }
    
    /// Normalize invite code (uppercase, trim whitespace)
    /// - Parameter code: Code to normalize
    /// - Returns: Normalized code
    static func normalize(_ code: String) -> String {
        return code.uppercased().trimmingCharacters(in: .whitespaces)
    }
}




