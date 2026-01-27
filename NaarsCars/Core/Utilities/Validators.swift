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
}
