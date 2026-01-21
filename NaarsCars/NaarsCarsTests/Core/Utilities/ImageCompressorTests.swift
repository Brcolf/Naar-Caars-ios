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
        // Create a large image (1000x1000)
        let largeImage = createTestImage(width: 1000, height: 1000)
        
        // Compress with avatar preset (max 400px)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .avatar) else {
            XCTFail("Compression should succeed")
            return
        }
        
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let maxDimension = max(compressedImage.size.width, compressedImage.size.height)
        XCTAssertLessThanOrEqual(maxDimension, 400, "Avatar should be max 400px")
    }
    
    func testAvatarPresetOutputSizeIsUnderMaxBytes() {
        // Create a large image
        let largeImage = createTestImage(width: 2000, height: 2000)
        
        // Compress with avatar preset (max 200KB)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .avatar) else {
            XCTFail("Compression should succeed")
            return
        }
        
        // Check that file size is under limit
        XCTAssertLessThanOrEqual(compressedData.count, 200 * 1024, "Avatar should be max 200KB")
    }
    
    // MARK: - MessageImage Preset Tests
    
    func testMessageImagePresetReducesDimensionsCorrectly() {
        // Create a very large image (3000x2000)
        let largeImage = createTestImage(width: 3000, height: 2000)
        
        // Compress with messageImage preset (max 1200px)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .messageImage) else {
            XCTFail("Compression should succeed")
            return
        }
        
        guard let compressedImage = UIImage(data: compressedData) else {
            XCTFail("Failed to create UIImage from compressed data")
            return
        }
        let maxDimension = max(compressedImage.size.width, compressedImage.size.height)
        XCTAssertLessThanOrEqual(maxDimension, 1200, "Message image should be max 1200px")
    }
    
    func testMessageImagePresetOutputSizeIsUnderMaxBytes() {
        // Create a large image
        let largeImage = createTestImage(width: 3000, height: 3000)
        
        // Compress with messageImage preset (max 800KB)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .messageImage) else {
            XCTFail("Compression should succeed")
            return
        }
        
        // Check that file size is under limit
        XCTAssertLessThanOrEqual(compressedData.count, 800 * 1024, "Message image should be max 800KB")
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
        
        // Compress with fullSize preset (max 1MB)
        guard let compressedData = ImageCompressor.compress(largeImage, preset: .fullSize) else {
            XCTFail("Compression should succeed")
            return
        }
        
        // Check that file size is under limit
        XCTAssertLessThanOrEqual(compressedData.count, 1024 * 1024, "Full size image should be max 1MB")
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
        XCTAssertLessThanOrEqual(maxDimension, 400, "Small image should still be under limit")
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

