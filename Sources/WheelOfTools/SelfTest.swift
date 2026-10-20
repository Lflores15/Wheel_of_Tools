#if DEBUG
import AppKit
import CoreImage
import SwiftUI
import WheelCore

/// Headless editor checks, run with WOT_SELFTEST=<dir>. Prints PASS/FAIL lines and exits non-zero on failure.
@MainActor
func runSelfTest(dir: String) -> Never {
    setvbuf(stdout, nil, _IONBF, 0)
    let root = URL(fileURLWithPath: dir)
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var failures = 0
    func report(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS " : "FAIL ") + name + (detail.isEmpty ? "" : " — " + detail))
        if !ok { failures += 1 }
    }

    /// RGBA at (x, y) with y measured from the top.
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return data.map(Int.init)
    }
    func fixture(_ name: String, color: String = "white") -> URL {
        let url = root.appendingPathComponent(name)
        _ = try? Shell.run("magick", ["-size", "400x300", "xc:" + color, url.path])
        return url
    }
    func model(_ url: URL, _ mode: EditMode) -> EditorModel { EditorModel(url: url, mode: mode)! }
    func reload(_ url: URL) -> CGImage? { loadCGImage(url) }
    func savedFile(_ m: EditorModel, of src: URL) -> URL? {
        m.save()
        let ext = ["jpg", "jpeg"].contains(src.pathExtension.lowercased()) ? "jpg" : "png"
        let out = src.deletingLastPathComponent().appendingPathComponent(
            src.deletingPathExtension().lastPathComponent + " edited." + ext)
        return FileManager.default.fileExists(atPath: out.path) ? out : nil
    }

    // Crop: exact size, and it takes the requested region (top-left red square on white).
    do {
        let src = root.appendingPathComponent("crop.png")
        _ = try? Shell.run("magick", ["-size", "400x300", "xc:white", "-fill", "red", "-draw", "rectangle 0,0 49,49", src.path])
        let m = model(src, .crop)
        m.drag = CGRect(x: 10, y: 10, width: 100, height: 50)
        m.applyCrop()
        report("crop size", m.image.width == 100 && m.image.height == 50, "\(m.image.width)x\(m.image.height)")
        report("crop region (top-left stays red, not flipped)",
               pixel(m.image, 5, 5)[0] > 200 && pixel(m.image, 5, 5)[1] < 50 && pixel(m.image, 90, 45)[1] > 200)
        let out = savedFile(m, of: src)
        report("crop save beside original", out != nil && reload(out!)?.width == 100)
    }

    // Redact: black in the top-left only.
    do {
        let src = fixture("redact.png")
        let m = model(src, .redact)
        m.drag = CGRect(x: 0, y: 0, width: 100, height: 60)
        m.applyRedact()
        report("redact top-left black", pixel(m.image, 20, 20)[0] < 10)
        report("redact bottom-left untouched (y not flipped)", pixel(m.image, 20, 280)[0] > 245)
        m.undo()
        report("undo restores", pixel(m.image, 20, 20)[0] > 245)
    }

    // Annotate: pen stroke and box are red.
    do {
        let src = fixture("annotate.jpg")
        let m = model(src, .annotate)
        m.path = [CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)]
        m.commitAnnotation()
        let p = pixel(m.image, 100, 100)
        report("annotate pen is red", p[0] > 200 && p[1] < 90 && p[2] < 90, "\(p)")
        m.useBox = true
        m.drag = CGRect(x: 200, y: 150, width: 100, height: 80)
        m.commitAnnotation()
        let b = pixel(m.image, 250, 150)
        report("annotate box edge is red", b[0] > 200 && b[1] < 90, "\(b)")
        report("annotate box interior untouched", pixel(m.image, 250, 190)[1] > 240)
        let out = savedFile(m, of: src)
        report("annotate save as jpg", out?.pathExtension == "jpg" && out.flatMap(reload) != nil)
    }

    // Adjust: brightness change alters pixels.
    do {
        let src = fixture("adjust.png", color: "gray(100)")
        let m = model(src, .adjust)
        let before = pixel(m.image, 50, 50)[0]
        m.brightness = 0.3
        m.applyAdjust()
        let after = pixel(m.image, 50, 50)[0]
        report("adjust brightness", after > before + 30, "\(before) -> \(after)")
        report("adjust sliders reset", m.brightness == 0)
    }

    // Background: needs a real subject.
    do {
        let pics = (try? FileManager.default.contentsOfDirectory(atPath: "/Library/User Pictures/Animals")) ?? []
        if let pic = pics.first(where: { $0.hasSuffix(".heic") || $0.hasSuffix(".jpg") }) {
            let src = root.appendingPathComponent("subject." + (pic as NSString).pathExtension)
            let real = URL(fileURLWithPath: "/Library/User Pictures/Animals/" + pic).resolvingSymlinksInPath()
            try? Data(contentsOf: real).write(to: src)
            guard let m = EditorModel(url: src, mode: .background) else { report("background (load photo)", false); print("FAIL"); exit(1) }
            m.fill = Color(red: 0, green: 1, blue: 0)
            m.applyBackground()
            if m.canUndo {
                let corner = pixel(m.image, 2, 2)
                report("background corner replaced with fill", corner[1] > 200 && corner[0] < 60, "\(corner)")
                let center = pixel(m.image, m.image.width / 2, m.image.height / 2)
                report("background keeps subject", !(center[1] > 200 && center[0] < 60), "\(center)")
            } else {
                report("background (Vision found a subject)", false, m.status)
            }
        } else { report("background (no sample photo found)", false) }
    }

    // QR: generate a real code, read it back.
    do {
        let payload = "https://example.com/wheel"
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let cg = CIContext().createCGImage(scaled, from: scaled.extent)!
        let url = root.appendingPathComponent("qr.png")
        try? writeImage(cg, to: url)
        let found = (try? Tools.readQR(url)) ?? []
        report("qr round-trip", found == [payload], "\(found)")
        let result = try? Tools.run(.qr, on: [url])
        report("qr tool text", result?.text == payload)
    }

    print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}

#endif
