//
//  UIImage+Resize.swift
//  NaarsCars
//
//  Convenience extension for resizing images before upload
//

import UIKit

extension UIImage {
    /// Returns a resized copy of the image if either dimension exceeds `maxDimension`.
    /// The aspect ratio is preserved. If the image is already within bounds, returns `self`.
    func resizedForUpload(maxDimension: CGFloat = 1920) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }
        
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
