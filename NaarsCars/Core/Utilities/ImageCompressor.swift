//
//  ImageCompressor.swift
//  NaarsCars
//
//  Image compression utility with presets for different use cases
//

#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
typealias UIImage = NSImage

// NSImage extension to provide UIImage-like API for macOS
extension NSImage {
    var size: CGSize {
        guard let rep = self.representations.first else { return .zero }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
    
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
    
    func draw(in rect: NSRect, from fromRect: NSRect, operation op: NSCompositingOperation, fraction delta: CGFloat) {
        self.draw(in: rect, from: fromRect, operation: op, fraction: delta)
    }
}
#endif

/// Image compression presets per FR-047
enum ImagePreset {
    case avatar
    case messageImage
    case fullSize
    
    /// Maximum dimension (longest side) in pixels
    var maxDimension: CGFloat {
        switch self {
        case .avatar: return 400
        case .messageImage: return 1200
        case .fullSize: return 2000
        }
    }
    
    /// Maximum file size in bytes
    var maxBytes: Int {
        switch self {
        case .avatar: return 200 * 1024      // 200KB
        case .messageImage: return 500 * 1024 // 500KB
        case .fullSize: return 1024 * 1024    // 1MB
        }
    }
    
    /// Initial JPEG quality (0.0 to 1.0)
    var initialQuality: CGFloat {
        switch self {
        case .avatar: return 0.8
        case .messageImage: return 0.7
        case .fullSize: return 0.8
        }
    }
}

/// Utility for compressing images to meet size and dimension requirements
struct ImageCompressor {
    /// Compress an image using the specified preset
    /// - Parameters:
    ///   - image: The UIImage to compress
    ///   - preset: The compression preset to use
    /// - Returns: Compressed image data as JPEG, or nil if compression fails
    static func compress(_ image: UIImage, preset: ImagePreset) -> Data? {
        // Step 1: Resize image to meet max dimension requirement
        let resizedImage = resize(image, maxDimension: preset.maxDimension)
        
        // Step 2: Compress with iterative quality reduction to meet size target
        var quality = preset.initialQuality
        let minQuality: CGFloat = 0.1
        
        while quality >= minQuality {
            guard let jpegData = resizedImage.jpegData(compressionQuality: quality) else {
                return nil
            }
            
            // Check if we meet the size requirement
            if jpegData.count <= preset.maxBytes {
                return jpegData
            }
            
            // Reduce quality by 0.1 and try again
            quality -= 0.1
        }
        
        // If we couldn't compress enough, return nil
        return nil
    }
    
    /// Resize image to fit within maximum dimension while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The image to resize
    ///   - maxDimension: Maximum dimension (longest side) in pixels
    /// - Returns: Resized UIImage
    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        // If image is already smaller than max dimension, return as-is
        if max(size.width, size.height) <= maxDimension {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        
        if size.width > size.height {
            // Landscape: width is the limiting factor
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Portrait or square: height is the limiting factor
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        #if os(iOS) || os(tvOS) || os(watchOS)
        // Use UIGraphicsImageRenderer for high-quality resizing on iOS
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        #elseif os(macOS)
        // Use NSGraphicsContext for macOS
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .sourceOver,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        return resizedImage
        #endif
    }
}

