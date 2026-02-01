//
//  ImageCompressorTests.swift
//  NaarsCarsTests
//
//  Unit tests for ImageCompressor
//

import XCTest
@testable import NaarsCars
import UIKit

final class ImageCompressorTests: XCTestCase {
    
    /// Create a test image with specified dimensions
    private func createTestImage(width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - Avatar Preset Tests
    
    func testAvatarPresetReducesDimensionsCorrectly() {
        // Create a very large image (4000x4000)
        let largeImage = createTestImage(width: 4000, height: 4000)
        
        // Compress with avatar preset (max 1024px)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .avatar) else {
            XCTFail("Compression should succeed")
            return
        }
        
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let maxDimension = max(compressedImage.size.width, compressedImage.size.height)
        XCTAssertEqual(maxDimension, 1024, accuracy: 0.5, "Avatar should resize to 1024px max")
    }
    
    func testAvatarPresetOutputSizeIsUnderMaxBytes() {
        // Verify avatar preset limits for high-quality uploads
        XCTAssertEqual(ImagePreset.avatar.maxDimension, 1024, "Avatar max dimension should be 1024px")
        XCTAssertEqual(ImagePreset.avatar.maxBytes, 1 * 1024 * 1024, "Avatar max bytes should be 1MB")
    }
    
    // MARK: - MessageImage Preset Tests
    
    func testMessageImagePresetReducesDimensionsCorrectly() {
        // Create a very large image (6000x4000)
        let largeImage = createTestImage(width: 6000, height: 4000)
        
        // Compress with messageImage preset (max 2048px)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .messageImage) else {
            XCTFail("Compression should succeed")
            return
        }
        
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let maxDimension = max(compressedImage.size.width, compressedImage.size.height)
        XCTAssertEqual(maxDimension, 2048, accuracy: 0.5, "Message image should resize to 2048px max")
    }
    
    func testMessageImagePresetOutputSizeIsUnderMaxBytes() {
        // Verify message image preset limits for Town Hall uploads
        XCTAssertEqual(ImagePreset.messageImage.maxDimension, 2048, "Message image max dimension should be 2048px")
        XCTAssertEqual(ImagePreset.messageImage.maxBytes, 2_621_440, "Message image max bytes should be 2.5MB")
    }
    
    // MARK: - FullSize Preset Tests
    
    func testFullSizePresetReducesDimensionsCorrectly() {
        // Create a very large image (4000x3000)
        let largeImage = createTestImage(width: 4000, height: 3000)
        
        // Compress with fullSize preset (max 2000px)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .fullSize) else {
            XCTFail("Compression should succeed")
            return
        }
        
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let maxDimension = max(compressedImage.size.width, compressedImage.size.height)
        XCTAssertLessThanOrEqual(maxDimension, 2000, "Full size image should be max 2000px")
    }
    
    func testFullSizePresetOutputSizeIsUnderMaxBytes() {
        // Create a large image
        let largeImage = createTestImage(width: 4000, height: 4000)
        
        // Compress with fullSize preset (max 2MB)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .fullSize) else {
            XCTFail("Compression should succeed")
            return
        }
        
        // Check that file size is under limit
        XCTAssertLessThanOrEqual(compressedData.count, 2 * 1024 * 1024, "Full size image should be max 2MB")
    }
    
    // MARK: - Edge Cases
    
    func testSmallImageIsNotResized() {
        // Create a small image (200x200) - already under avatar limit
        let smallImage = createTestImage(width: 200, height: 200)
        
        // Compress with avatar preset
        guard let compressedData = ImageCompressor.compress(smallImage, preset: .avatar) else {
            XCTFail("Compression should succeed")
            return
        }
        
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let maxDimension = max(compressedImage.size.width, compressedImage.size.height)
        XCTAssertLessThanOrEqual(maxDimension, 1024, "Small image should still be under limit")
    }
    
    func testAspectRatioIsMaintained() {
        // Create a wide image (2000x500)
        let wideImage = createTestImage(width: 2000, height: 500)
        
        // Compress with messageImage preset
        guard let compressedData = ImageCompressor.compress(wideImage, preset: .messageImage) else {
            XCTFail("Compression should succeed")
            return
        }
        
        // Check aspect ratio is maintained (2000/500 = 4.0)
        let originalAspectRatio = 2000.0 / 500.0
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let compressedAspectRatio = compressedImage.size.width / compressedImage.size.height
        XCTAssertEqual(compressedAspectRatio, originalAspectRatio, accuracy: 0.1, "Aspect ratio should be maintained")
    }
}

