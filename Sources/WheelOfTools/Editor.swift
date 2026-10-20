import SwiftUI
import AppKit
import CoreImage
import Vision
import WheelCore

enum EditMode: String, CaseIterable, Identifiable {
    case crop, adjust, annotate, background, redact
    var id: String { rawValue }
    var label: String { Tool(rawValue: rawValue)?.label ?? rawValue }
    var symbol: String { Tool(rawValue: rawValue)?.symbol ?? "questionmark" }
}

private let ciContext = CIContext()

@MainActor
final class EditorModel: ObservableObject {
    let url: URL
    @Published var image: CGImage
    @Published var mode: EditMode
    @Published var drag: CGRect?          // image pixel coordinates, top-left origin
    @Published var path: [CGPoint] = []   // in-progress pen stroke
    @Published var useBox = false         // annotate: rectangle instead of pen
    @Published var brightness = 0.0
    @Published var contrast = 1.0
    @Published var saturation = 1.0
    @Published var fill = Color.white
    @Published var status = ""
    private var history: [CGImage] = []

    var canUndo: Bool { !history.isEmpty }
    var size: CGSize { CGSize(width: image.width, height: image.height) }

    init?(url: URL, mode: EditMode) {
        guard let cg = loadCGImage(url) else { return nil }
        self.url = url
        self.image = cg
        self.mode = mode
    }

    /// The image as shown on the canvas (adjust sliders preview live).
    var displayImage: CGImage {
        guard mode == .adjust, brightness != 0 || contrast != 1 || saturation != 1 else { return image }
        return adjusted() ?? image
    }

    private func adjusted() -> CGImage? {
        let input = CIImage(cgImage: image)
        let out = input.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation])
        return ciContext.createCGImage(out, from: input.extent)
    }

    private func push(_ new: CGImage?) {
        guard let new else { status = "That didn't work"; return }
        history.append(image)
        image = new
        drag = nil
        path = []
        status = ""
    }

    func undo() {
        guard let last = history.popLast() else { return }
        image = last
        drag = nil
    }

    /// Draws into a copy of the image using top-left-origin pixel coordinates.
    private func render(_ body: (CGContext) -> Void) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        body(ctx)
        return ctx.makeImage()
    }

    func applyCrop() {
        guard let r = drag?.integral.intersection(CGRect(origin: .zero, size: size)), r.width > 2, r.height > 2 else {
            status = "Drag a rectangle to crop"; return
        }
        push(image.cropping(to: r))
    }

    func applyRedact() {
        guard let r = drag, r.width > 1, r.height > 1 else { drag = nil; return }
        push(render { ctx in ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(r) })
    }

    func commitAnnotation() {
        let lineWidth = max(3, max(size.width, size.height) / 250)
        if useBox, let r = drag, r.width > 1 {
            push(render { ctx in
                ctx.setStrokeColor(NSColor.systemRed.cgColor); ctx.setLineWidth(lineWidth); ctx.stroke(r)
            })
        } else if path.count > 1 {
            let pts = path
            push(render { ctx in
                ctx.setStrokeColor(NSColor.systemRed.cgColor); ctx.setLineWidth(lineWidth)
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                ctx.addLines(between: pts); ctx.strokePath()
            })
        } else { drag = nil; path = [] }
    }

    func applyAdjust() {
        guard let out = adjusted() else { return }
        push(out)
        brightness = 0; contrast = 1; saturation = 1
    }

    func applyBackground() {
        status = "Finding subject…"
        do {
            let handler = VNImageRequestHandler(cgImage: image)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let result = request.results?.first else { status = "No subject found"; return }
            let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let input = CIImage(cgImage: image)
            guard let color = CIColor(color: NSColor(fill)) else { return }
            let background = CIImage(color: color).cropped(to: input.extent)
            let out = input.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: CIImage(cvPixelBuffer: buffer)])
            push(ciContext.createCGImage(out, from: input.extent))
        } catch {
            status = error.localizedDescription
        }
    }

    func save() {
        let ext = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? "jpg" : "png"
        let out = uniqueURL(dir: url.deletingLastPathComponent(),
                            base: url.deletingPathExtension().lastPathComponent + " edited", ext: ext)
        do {
            try writeImage(displayImage, to: out)
            NSWorkspace.shared.activateFileViewerSelecting([out])
            status = "Saved \(out.lastPathComponent)"
        } catch { status = error.localizedDescription }
    }
}

/// Maps between canvas points and image pixels for an aspect-fit image.
private struct Fit {
    let scale: CGFloat, ox: CGFloat, oy: CGFloat
    init(view: CGSize, image: CGSize) {
        scale = min(view.width / image.width, view.height / image.height)
        ox = (view.width - image.width * scale) / 2
        oy = (view.height - image.height * scale) / 2
    }
    func toImage(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max((p.x - ox) / scale, 0), size.width), y: min(max((p.y - oy) / scale, 0), size.height))
    }
    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * scale, y: oy + p.y * scale) }
    func toView(_ r: CGRect) -> CGRect {
        CGRect(x: ox + r.minX * scale, y: oy + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            canvas.background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("", selection: $model.mode) {
                ForEach(EditMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
            .onChange(of: model.mode) { _, _ in model.drag = nil }

            switch model.mode {
            case .crop: Button("Apply Crop") { model.applyCrop() }.disabled(model.drag == nil)
            case .redact: Text("Drag over anything to black it out").foregroundStyle(.secondary)
            case .annotate:
                Picker("", selection: $model.useBox) {
                    Text("Pen").tag(false); Text("Box").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 110)
            case .adjust:
                slider("Brightness", $model.brightness, -0.5...0.5)
                slider("Contrast", $model.contrast, 0.5...1.5)
                slider("Saturation", $model.saturation, 0...2)
                Button("Apply") { model.applyAdjust() }
            case .background:
                ColorPicker("Fill", selection: $model.fill)
                Button("Replace Background") { model.applyBackground() }
            }
            Spacer()
            Text(model.status).foregroundStyle(.secondary).lineLimit(1)
            Button("Undo") { model.undo() }.disabled(!model.canUndo).keyboardShortcut("z")
            Button("Save") { model.save() }.keyboardShortcut("s").buttonStyle(.borderedProminent)
        }
        .padding(10)
    }

    private func slider(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(spacing: 0) {
            Slider(value: value, in: range).frame(width: 90)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = Fit(view: geo.size, image: model.size)
            ZStack {
                Image(decorative: model.displayImage, scale: 1)
                    .resizable()
                    .frame(width: model.size.width * fit.scale, height: model.size.height * fit.scale)
                Canvas { ctx, size in
                    let imageRect = fit.toView(CGRect(origin: .zero, size: model.size))
                    if model.mode == .crop, let r = model.drag {
                        var dim = Path(imageRect)
                        dim.addRect(fit.toView(r))
                        ctx.fill(dim, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                        ctx.stroke(Path(fit.toView(r)), with: .color(.white), lineWidth: 1.5)
                    } else if model.mode == .redact, let r = model.drag {
                        ctx.fill(Path(fit.toView(r)), with: .color(.black))
                    } else if model.mode == .annotate {
                        if model.useBox, let r = model.drag {
                            ctx.stroke(Path(fit.toView(r)), with: .color(.red), lineWidth: 3)
                        } else if model.path.count > 1 {
                            var p = Path()
                            p.addLines(model.path.map(fit.toView))
                            ctx.stroke(p, with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let a = fit.toImage(v.startLocation, in: model.size), b = fit.toImage(v.location, in: model.size)
                    switch model.mode {
                    case .crop, .redact: model.drag = rect(a, b)
                    case .annotate:
                        if model.useBox { model.drag = rect(a, b) } else { model.path.append(b) }
                    default: break
                    }
                }
                .onEnded { _ in
                    switch model.mode {
                    case .redact: model.applyRedact()
                    case .annotate: model.commitAnnotation()
                    default: break
                    }
                })
        }
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

@MainActor
enum EditorWindows {
    private static var windows: [NSWindow] = []

    static func open(url: URL, mode: EditMode) -> String? {
        guard let model = EditorModel(url: url, mode: mode) else { return "Could not open \(url.lastPathComponent)" }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return nil
    }
}
