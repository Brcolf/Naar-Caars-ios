//
//  QRCodeRenderer.swift
//  NaarsCars
//
//  Generates a QR code image from text (generation only; nothing is scanned)
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum QRCodeRenderer {
    private static let context = CIContext()

    /// A square QR code of about `dimension` points on a side, or nil when `text` cannot be encoded.
    /// Show it with `.interpolation(.none)` so the modules stay sharp.
    static func image(for text: String, dimension: CGFloat) -> UIImage? {
        guard !text.isEmpty, dimension > 0 else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent
        guard extent.width > 0 else { return nil }
        let scale = dimension / extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
