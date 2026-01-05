//
//  Validators.swift
//  NaarsCars
//
//  Input validation helpers for forms and user input
//

import Foundation

/// Utility for validating and formatting user input
enum Validators {
    
    // MARK: - Phone Number Validation
    
    /// Validates phone number (US or international)
    /// - Parameter input: Phone number string (may include formatting)
    /// - Returns: true if valid (10-15 digits)
    static func isValidPhoneNumber(_ input: String) -> Bool {
        let digits = input.filter { $0.isNumber }
        // Accept 10 digits (US) or 11-15 digits (international with country code)
        return digits.count >= 10 && digits.count <= 15
    }
    
    /// Formats phone number for storage (E.164 format)
    /// - Parameter input: Phone number string (may include formatting)
    /// - Returns: E.164 formatted string (e.g., "+12065551234") or nil if invalid
    static func formatPhoneForStorage(_ input: String) -> String? {
        let digits = input.filter { $0.isNumber }
        
        if digits.count == 10 {
            // Assume US - add +1 prefix
            return "+1\(digits)"
        } else if digits.count == 11 && digits.first == "1" {
            // US with country code already
            return "+\(digits)"
        } else if digits.count >= 11 && digits.count <= 15 {
            // International - assume has country code
            return "+\(digits)"
        }
        
        return nil
    }
    
    /// Formats phone number for display
    /// - Parameters:
    ///   - e164: E.164 formatted phone number (e.g., "+12065551234")
    ///   - masked: If true, mask all but last 4 digits (e.g., "(•••) •••-1234")
    /// - Returns: Formatted display string
    static func displayPhoneNumber(_ e164: String, masked: Bool = false) -> String {
        let digits = e164.filter { $0.isNumber }
        guard digits.count >= 10 else { return e164 }
        
        let last10 = String(digits.suffix(10))
        
        if masked {
            // Mask all but last 4 digits: (•••) •••-1234
            return "(•••) •••-\(last10.suffix(4))"
        } else {
            // Standard US format: (206) 555-1234
            return "(\(last10.prefix(3))) \(last10.dropFirst(3).prefix(3))-\(last10.suffix(4))"
        }
    }
    
    // MARK: - Email Validation
    
    /// Validates email address format
    /// - Parameter email: Email string to validate
    /// - Returns: true if valid email format
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - Password Validation
    
    /// Validates password strength
    /// - Parameter password: Password string to validate
    /// - Returns: true if password meets requirements (min 8 chars, at least one letter and one number)
    static func isValidPassword(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        
        let hasLetter = password.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil
        
        return hasLetter && hasNumber
    }
    
    // MARK: - Invite Code Validation
    
    /// Validates invite code format
    /// Format: NC + 8 alphanumeric characters (uppercase)
    /// Character set: A-Z, 0-9 (excluding confusing: 0/O, 1/I/L)
    /// - Parameter code: Invite code string to validate
    /// - Returns: true if valid format
    static func isValidInviteCodeFormat(_ code: String) -> Bool {
        let normalized = code.uppercased()
        
        // Must start with "NC"
        guard normalized.hasPrefix("NC") else { return false }
        
        // Must be exactly 10 characters (NC + 8)
        guard normalized.count == 10 else { return false }
        
        // Check remaining 8 characters are alphanumeric (excluding 0, O, 1, I, L)
        let allowedChars = CharacterSet(charactersIn: "23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        let codePart = String(normalized.dropFirst(2))
        
        return codePart.unicodeScalars.allSatisfy { allowedChars.contains($0) }
    }
    
    /// Normalizes invite code to uppercase and removes whitespace
    /// - Parameter code: Invite code string
    /// - Returns: Normalized code
    static func normalizeInviteCode(_ code: String) -> String {
        return code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

