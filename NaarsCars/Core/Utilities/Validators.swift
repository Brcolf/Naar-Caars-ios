//
//  Validators.swift
//  NaarsCars
//
//  Input validation utilities for phone numbers and other fields
//

import Foundation
import PhoneNumberKit

/// Validation utilities for user input
enum Validators {
    private static let phoneNumberKit = PhoneNumberUtility()
    
    // MARK: - Phone Number Validation
    
    /// Validate phone number format
    /// Accepts 10-15 digits (supports international numbers)
    /// - Parameter phone: Phone number string
    /// - Returns: true if valid, false otherwise
    static func isValidPhoneNumber(_ phone: String) -> Bool {
        do {
            _ = try phoneNumberKit.parse(phone)
            return true
        } catch {
            return false
        }
    }
    
    /// Format phone number for storage in E.164 format
    /// - Parameter phone: Phone number string (any format)
    /// - Returns: E.164 formatted string (+1XXXXXXXXXX) or nil if invalid
    static func formatPhoneForStorage(_ phone: String) -> String? {
        do {
            let number = try phoneNumberKit.parse(phone)
            return phoneNumberKit.format(number, toType: .e164)
        } catch {
            return nil
        }
    }
    
    /// Format phone number for display
    /// - Parameters:
    ///   - phone: Phone number string (E.164 format expected)
    ///   - masked: If true, mask all but last 4 digits
    /// - Returns: Formatted display string
    static func displayPhoneNumber(_ phone: String, masked: Bool = false) -> String {
        let digitsOnly = phone.filter { $0.isNumber }
        
        if masked {
            // Masked format: (•••) •••-1234 (showing last 4 only)
            let lastFour = String(digitsOnly.suffix(4))
            return "(•••) •••-\(lastFour)"
        }

        if let number = try? phoneNumberKit.parse(phone) {
            return phoneNumberKit.format(number, toType: .international)
        }

        return phone
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

    // MARK: - Input Sanitization

    /// Checks that user-supplied text does not contain control characters or
    /// zero-width/invisible Unicode that could be used for prompt injection or
    /// UI spoofing. Normal punctuation, emoji, and international scripts are allowed.
    static func isSafeUserInput(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Allow normal whitespace (space, tab, newline)
            if scalar == "\u{0020}" || scalar == "\u{0009}" || scalar == "\u{000A}" || scalar == "\u{000D}" {
                continue
            }
            // Block C0/C1 control characters
            if scalar.properties.generalCategory == .control {
                return false
            }
            // Block zero-width / invisible formatting characters commonly used for injection
            let zeroWidthChars: [Unicode.Scalar] = [
                "\u{200B}", // zero-width space
                "\u{200C}", // zero-width non-joiner
                "\u{200D}", // zero-width joiner (allow in emoji sequences — actually keep this)
                "\u{FEFF}", // byte-order mark
                "\u{2028}", // line separator
                "\u{2029}", // paragraph separator
                "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", // bidi overrides
                "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", // bidi isolates
            ]
            if zeroWidthChars.contains(scalar) && scalar != "\u{200D}" {
                return false
            }
        }
        return true
    }

    /// Sanitizes user input by stripping unsafe characters and limiting length.
    /// Returns the cleaned string.
    static func sanitizeUserInput(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = String(trimmed.unicodeScalars.filter { scalar in
            // Keep normal whitespace
            if scalar == "\u{0020}" || scalar == "\u{0009}" || scalar == "\u{000A}" || scalar == "\u{000D}" {
                return true
            }
            // Drop control characters
            if scalar.properties.generalCategory == .control { return false }
            // Drop bidi overrides
            let bidi: [Unicode.Scalar] = [
                "\u{200B}", "\u{200C}", "\u{FEFF}",
                "\u{2028}", "\u{2029}",
                "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
            ]
            if bidi.contains(scalar) { return false }
            return true
        })
        return String(cleaned.prefix(maxLength))
    }
}
