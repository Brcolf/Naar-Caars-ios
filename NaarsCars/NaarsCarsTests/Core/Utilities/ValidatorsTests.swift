//
//  ValidatorsTests.swift
//  NaarsCarsTests
//
//  Unit tests for Validators utility
//

import XCTest
@testable import NaarsCars

final class ValidatorsTests: XCTestCase {
    
    // MARK: - Phone Number Validation Tests
    
    func testIsValidPhoneNumber_ValidUS_ReturnsTrue() {
        // Test various valid US phone number formats
        XCTAssertTrue(Validators.isValidPhoneNumber("1234567890")) // 10 digits
        XCTAssertTrue(Validators.isValidPhoneNumber("(123) 456-7890")) // Formatted
        XCTAssertTrue(Validators.isValidPhoneNumber("123-456-7890")) // Dashed
        XCTAssertTrue(Validators.isValidPhoneNumber("123.456.7890")) // Dotted
        XCTAssertTrue(Validators.isValidPhoneNumber("+1 123 456 7890")) // With country code
        XCTAssertTrue(Validators.isValidPhoneNumber("11234567890")) // 11 digits with leading 1
    }
    
    func testIsValidPhoneNumber_TooShort_ReturnsFalse() {
        // Test numbers that are too short
        XCTAssertFalse(Validators.isValidPhoneNumber("123456789")) // 9 digits
        XCTAssertFalse(Validators.isValidPhoneNumber("12345")) // 5 digits
        XCTAssertFalse(Validators.isValidPhoneNumber("")) // Empty
    }
    
    func testIsValidPhoneNumber_TooLong_ReturnsFalse() {
        // Test numbers that are too long
        XCTAssertFalse(Validators.isValidPhoneNumber("1234567890123456")) // 16 digits
    }
    
    func testIsValidPhoneNumber_International_ReturnsTrue() {
        // Test international numbers (11-15 digits)
        XCTAssertTrue(Validators.isValidPhoneNumber("441234567890")) // UK: 12 digits
        XCTAssertTrue(Validators.isValidPhoneNumber("8613800138000")) // China: 13 digits
    }
    
    // MARK: - Phone Formatting Tests
    
    func testFormatPhoneForStorage_ReturnsE164() {
        // Test E.164 formatting
        let result1 = Validators.formatPhoneForStorage("1234567890")
        XCTAssertEqual(result1, "+11234567890", "10-digit US number should add +1")
        
        let result2 = Validators.formatPhoneForStorage("11234567890")
        XCTAssertEqual(result2, "+11234567890", "11-digit US number should add +")
        
        let result3 = Validators.formatPhoneForStorage("441234567890")
        XCTAssertEqual(result3, "+441234567890", "International number should add +")
    }
    
    func testFormatPhoneForStorage_Invalid_ReturnsNil() {
        // Test invalid numbers
        XCTAssertNil(Validators.formatPhoneForStorage("123")) // Too short
        XCTAssertNil(Validators.formatPhoneForStorage("1234567890123456")) // Too long
    }
    
    // MARK: - Phone Display Tests
    
    func testDisplayPhoneNumber_Masked_ShowsLastFour() {
        let phone = "+11234567890"
        let masked = Validators.displayPhoneNumber(phone, masked: true)
        
        XCTAssertTrue(masked.contains("7890"), "Masked phone should show last 4 digits")
        XCTAssertTrue(masked.contains("•••"), "Masked phone should contain dots")
        XCTAssertFalse(masked.contains("123"), "Masked phone should not show first digits")
    }
    
    func testDisplayPhoneNumber_Unmasked_ShowsFullNumber() {
        let phone = "+11234567890"
        let unmasked = Validators.displayPhoneNumber(phone, masked: false)
        
        XCTAssertTrue(unmasked.contains("123"), "Unmasked phone should show area code")
        XCTAssertTrue(unmasked.contains("456"), "Unmasked phone should show exchange")
        XCTAssertTrue(unmasked.contains("7890"), "Unmasked phone should show number")
    }
    
    func testDisplayPhoneNumber_International_FormatsCorrectly() {
        let phone = "+441234567890"
        let formatted = Validators.displayPhoneNumber(phone, masked: false)
        
        XCTAssertTrue(formatted.contains("+44"), "International number should show country code")
    }
}




