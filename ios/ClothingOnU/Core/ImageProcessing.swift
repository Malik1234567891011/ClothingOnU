import UIKit
import ImageIO

/// Image work that happens before anything is uploaded or stored.
enum ImageProcessing {
    /// Long edge sent to the server. 1280 px keeps faces and garment detail legible while
    /// keeping a 7-image request around 2 MB, well under the 4.4 MB server limit.
    static let uploadLongEdge: CGFloat = 1280
    static let uploadQuality: CGFloat = 0.8

    /// Decode, apply EXIF orientation, and downscale in one pass via ImageIO (memory-cheap,
    /// works for 48 MP camera photos without decoding the full bitmap).
    static func downsampled(_ data: Data, longEdge: CGFloat) -> UIImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Re-render a UIImage (which may carry an orientation) at most `longEdge` pixels on its long side.
    static func resized(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let size = image.pixelSize
        let scale = min(1, longEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        if scale == 1, image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG for upload: resized, orientation baked in.
    static func uploadJPEG(_ image: UIImage) -> Data? {
        resized(image, longEdge: uploadLongEdge).jpegData(compressionQuality: uploadQuality)
    }

    /// Crop to a rectangle given in unit coordinates (0...1, origin top-left).
    static func crop(_ image: UIImage, to unitRect: CGRect) -> UIImage {
        let upright = resized(image, longEdge: max(image.pixelSize.width, image.pixelSize.height))
        guard let cg = upright.cgImage else { return image }
        let clamped = unitRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let px = CGRect(
            x: clamped.minX * CGFloat(cg.width),
            y: clamped.minY * CGFloat(cg.height),
            width: clamped.width * CGFloat(cg.width),
            height: clamped.height * CGFloat(cg.height)
        ).integral
        guard px.width >= 8, px.height >= 8, let out = cg.cropping(to: px) else { return image }
        return UIImage(cgImage: out)
    }
}

extension UIImage {
    /// Average colour of the image's side edges: the studio backdrop of a render. Used behind the
    /// image so letterboxing blends in instead of showing bars.
    var backdropColor: UIColor {
        // Draw into a context with a known RGBA layout; UIGraphicsImageRenderer's layout is BGRA.
        let side = 16
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let cg = cgImage ?? ImageProcessing.resized(self, longEdge: 256).cgImage,
              let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return .gray }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var r = 0.0, g = 0.0, b = 0.0
        // Mid-height on the left and right edges: renders are vignetted, so corners read too dark.
        let corners = [(1, side / 3), (side - 2, side / 3), (1, side / 2), (side - 2, side / 2), (1, 2 * side / 3), (side - 2, 2 * side / 3)]
        for (x, y) in corners {
            let o = (y * side + x) * 4
            r += Double(px[o]); g += Double(px[o + 1]); b += Double(px[o + 2])
        }
        let n = Double(corners.count) * 255
        return UIColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
    }

    /// Size in pixels, accounting for orientation.
    var pixelSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }
}
