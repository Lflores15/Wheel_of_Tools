import Foundation
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Loads any image the system or ImageMagick can read, with EXIF orientation applied.
public func loadCGImage(_ url: URL) -> CGImage? {
    func native(_ u: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 20000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
    if let image = native(url) { return image }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: tmp) }
    guard (try? Shell.run("magick", [magickInput(url), "-auto-orient", tmp.path])) != nil else { return nil }
    return native(tmp)
}

public func writeImage(_ image: CGImage, to url: URL, quality: Double = 0.92) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
    let data = isJPEG
        ? rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        : rep.representation(using: .png, properties: [:])
    guard let data else { throw ToolError("Could not encode image") }
    try data.write(to: url)
}

/// Renders one PDF page to a bitmap, `scale` times its point size, on a white background.
public func renderPage(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
    let box = page.bounds(for: .mediaBox)
    let w = Int(box.width * scale), h = Int(box.height * scale)
    guard w > 0, h > 0,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()
}

public func pdfFromImages(_ images: [CGImage], to url: URL) throws {
    let doc = PDFDocument()
    for (i, cg) in images.enumerated() {
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        guard let page = PDFPage(image: img) else { throw ToolError("Could not build PDF page") }
        doc.insert(page, at: i)
    }
    guard doc.write(to: url) else { throw ToolError("Could not write PDF") }
}

/// Paginates plain text into a US-Letter PDF.
public func textToPDF(_ text: String, to url: URL) throws {
    let attr = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    let framesetter = CTFramesetterCreateWithAttributedString(attr)
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ToolError("Could not create PDF") }
    var index = 0
    repeat {
        ctx.beginPDFPage(nil)
        let path = CGPath(rect: box.insetBy(dx: 54, dy: 54), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: index, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
        let visible = CTFrameGetVisibleStringRange(frame)
        ctx.endPDFPage()
        if visible.length == 0 { break }
        index += visible.length
    } while index < attr.length
    ctx.closePDF()
}
