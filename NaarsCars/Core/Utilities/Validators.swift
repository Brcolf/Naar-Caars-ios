//
//  Validators.swift
//  NaarsCars
//
//  Input validation utilities for phone numbers and other fields
//

import Foundation

/// Validation utilities for user input
enum Validators {
    
    // MARK: - Phone Number Validation
    
    /// Validate phone number format
    /// Accepts 10-15 digits (supports international numbers)
    /// - Parameter phone: Phone number string
    /// - Returns: true if valid, false otherwise
    static func isValidPhoneNumber(_ phone: String) -> Bool {
        // Remove all non-digit characters
        let digitsOnly = phone.filter { $0.isNumber }
        
        // Check length: 10-15 digits (US: 10, International: 11-15 with country code)
        return digitsOnly.count >= 10 && digitsOnly.count <= 15
    }
    
    /// Format phone number for storage in E.164 format
    /// - Parameter phone: Phone number string (any format)
    /// - Returns: E.164 formatted string (+1XXXXXXXXXX) or nil if invalid
    static func formatPhoneForStorage(_ phone: String) -> String? {
        // Remove all non-digit characters
        let digitsOnly = phone.filter { $0.isNumber }
        
        guard digitsOnly.count >= 10 && digitsOnly.count <= 15 else {
            return nil
        }
        
        // If 10 digits, assume US number and add +1
        if digitsOnly.count == 10 {
            return "+1\(digitsOnly)"
        }
        
        // If 11 digits and starts with 1, assume US with country code
        if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+\(digitsOnly)"
        }
        
        // For international numbers (11-15 digits), add + prefix
        if digitsOnly.count >= 11 && digitsOnly.count <= 15 {
            // Check if already has country code indicator
            if digitsOnly.first == "1" {
                return "+\(digitsOnly)"
            }
            // Assume country code is present, add +
            return "+\(digitsOnly)"
        }
        
        return nil
    }
    
    /// Format phone number for display
    /// - Parameters:
    ///   - phone: Phone number string (E.164 format expected)
    ///   - masked: If true, mask all but last 4 digits
    /// - Returns: Formatted display string
    static func displayPhoneNumber(_ phone: String, masked: Bool = false) -> String {
        // Remove + and any non-digit characters
        let digitsOnly = phone.filter { $0.isNumber }
        
        guard digitsOnly.count >= 10 else {
            return phone // Return original if invalid
        }
        
        if masked {
            // Masked format: (•••) •••-1234 (showing last 4 only)
            let lastFour = String(digitsOnly.suffix(4))
            return "(•••) •••-\(lastFour)"
        } else {
            // Unmasked format: (XXX) XXX-XXXX for US numbers
            if digitsOnly.count == 10 || (digitsOnly.count == 11 && digitsOnly.hasPrefix("1")) {
                let areaCode = String(digitsOnly.suffix(10).prefix(3))
                let exchange = String(digitsOnly.suffix(7).prefix(3))
                let number = String(digitsOnly.suffix(4))
                return "(\(areaCode)) \(exchange)-\(number)"
            } else {
                // International format: +XX XXX XXX XXXX
                // For simplicity, just show with + prefix and spaces
                var formatted = "+"
                var remaining = digitsOnly
                
                // Add country code (1-3 digits)
                if remaining.count > 10 {
                    let countryCodeLength = remaining.count - 10
                    let countryCode = String(remaining.prefix(countryCodeLength))
                    formatted += countryCode + " "
                    remaining = String(remaining.dropFirst(countryCodeLength))
                }
                
                // Format remaining digits
                if remaining.count == 10 {
                    let areaCode = String(remaining.prefix(3))
                    let exchange = String(remaining.dropFirst(3).prefix(3))
                    let number = String(remaining.suffix(4))
                    formatted += "\(areaCode) \(exchange) \(number)"
                } else {
                    // Fallback: just add spaces every 3 digits
                    var spaced = ""
                    for (index, char) in remaining.enumerated() {
                        if index > 0 && index % 3 == 0 {
                            spaced += " "
                        }
                        spaced.append(char)
                    }
                    formatted += spaced
                }
                
                return formatted
            }
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
}
