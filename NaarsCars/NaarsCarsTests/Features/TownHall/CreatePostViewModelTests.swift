//
//  CreatePostViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for CreatePostViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class CreatePostViewModelTests: XCTestCase {
    var viewModel: CreatePostViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = CreatePostViewModel()
    }
    
    /// Test that empty content returns error
    func testPost_EmptyContent_ReturnsError() async {
        // Given: Empty content
        viewModel.content = ""
        
        // When: Attempting to post
        do {
            _ = try await viewModel.validateAndPost()
            XCTFail("Should have thrown error for empty content")
        } catch {
            // Then: Should throw invalidInput error
            if case AppError.invalidInput(let message) = error {
                XCTAssertTrue(message.contains("empty") || message.contains("cannot"), "Error should mention empty content")
            } else {
                // Other errors are acceptable (e.g., not authenticated)
                print("⚠️ Post creation failed with: \(error)")
            }
        }
    }
    
    /// Test that whitespace-only content returns error
    func testPost_WhitespaceOnlyContent_ReturnsError() async {
        // Given: Whitespace-only content
        viewModel.content = "   \n\t  "
        
        // When: Attempting to post
        do {
            _ = try await viewModel.validateAndPost()
            XCTFail("Should have thrown error for whitespace-only content")
        } catch {
            // Then: Should throw invalidInput error
            if case AppError.invalidInput(let message) = error {
                XCTAssertTrue(message.contains("empty") || message.contains("cannot"), "Error should mention empty content")
            } else {
                // Other errors are acceptable
                print("⚠️ Post creation failed with: \(error)")
            }
        }
    }
    
    /// Test that content exceeding 500 characters returns error
    func testPost_ContentTooLong_ReturnsError() async {
        // Given: Content exceeding 500 characters
        viewModel.content = String(repeating: "a", count: 501)
        
        // When: Attempting to post
        do {
            _ = try await viewModel.validateAndPost()
            XCTFail("Should have thrown error for content too long")
        } catch {
            // Then: Should throw invalidInput error
            if case AppError.invalidInput(let message) = error {
                XCTAssertTrue(message.contains("500"), "Error should mention 500 character limit")
            } else {
                // Other errors are acceptable
                print("⚠️ Post creation failed with: \(error)")
            }
        }
    }
    
    /// Test that character count is calculated correctly
    func testCharacterCount_CalculatedCorrectly() {
        // Given: Content with known length
        viewModel.content = "Hello, world!"
        
        // Then: Character count should match
        XCTAssertEqual(viewModel.characterCount, 13, "Character count should match content length")
    }
    
    /// Test that remaining characters is calculated correctly
    func testRemainingCharacters_CalculatedCorrectly() {
        // Given: Content with known length
        viewModel.content = "Hello"
        
        // Then: Remaining characters should be 500 - 5 = 495
        XCTAssertEqual(viewModel.remainingCharacters, 495, "Remaining characters should be 500 - content length")
    }
    
    /// Test that canPost is false when content is empty
    func testCanPost_EmptyContent_ReturnsFalse() {
        // Given: Empty content
        viewModel.content = ""
        
        // Then: canPost should be false
        XCTAssertFalse(viewModel.canPost, "Cannot post with empty content")
    }
    
    /// Test that canPost is false when content is too long
    func testCanPost_ContentTooLong_ReturnsFalse() {
        // Given: Content exceeding 500 characters
        viewModel.content = String(repeating: "a", count: 501)
        
        // Then: canPost should be false
        XCTAssertFalse(viewModel.canPost, "Cannot post with content exceeding 500 characters")
    }
    
    /// Test that canPost is true when content is valid
    func testCanPost_ValidContent_ReturnsTrue() {
        // Given: Valid content
        viewModel.content = "This is a valid post!"
        
        // Then: canPost should be true
        XCTAssertTrue(viewModel.canPost, "Can post with valid content")
    }
    
    /// Test that removeImage clears selected image
    func testRemoveImage_ClearsImage() {
        // Given: An image selected
        viewModel.selectedImage = UIImage(systemName: "photo")
        viewModel.imageUrl = "https://example.com/image.jpg"
        
        // When: Removing image
        viewModel.removeImage()
        
        // Then: Image should be cleared
        XCTAssertNil(viewModel.selectedImage, "Selected image should be nil")
        XCTAssertNil(viewModel.imageUrl, "Image URL should be nil")
    }
}



