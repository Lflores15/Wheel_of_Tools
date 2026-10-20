import AppKit
import WheelCore

struct WheelItem {
    let label: String
    let symbol: String
}

/// The ring itself: draws labels and the hovered segment, and accepts file drops per segment.
final class WheelView: NSView {
    /// 1.0 is the default size; everything below is derived from it.
    static var scale: CGFloat = 1
    static var outer: CGFloat { 200 * scale }
    static var inner: CGFloat { 72 * scale }

    var items: [WheelItem] = [] { didSet { hovered = nil; needsDisplay = true } }
    var title = ""
    var fileCount = 1
    var sizeText = ""
    var onDrop: ((Int, [URL]) -> Void)?
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    private var step: CGFloat { 360 / CGFloat(max(items.count, 1)) }

    /// Rounded "petal" tile for segment i, with a fixed gap to its neighbours.
    static func tile(_ i: Int, of n: Int, center: CGPoint) -> CGPath {
        let step = 360 / CGFloat(n)
        let corner: CGFloat = 12 * scale, gap: CGFloat = 8 * scale
        let ri = inner + 9 * scale + corner, ro = outer - 13 * scale - corner
        // Constant-width gaps: each arc backs off by the same distance, not the same angle.
        let k = gap / 2 + corner
        func ang(_ i: Int, _ r: CGFloat, _ sign: CGFloat) -> CGFloat {
            (90 - CGFloat(i) * step + sign * k / r * 180 / .pi) * .pi / 180
        }
        let path = CGMutablePath()
        path.addArc(center: center, radius: ro, startAngle: ang(i, ro, -1), endAngle: ang(i + 1, ro, 1), clockwise: true)
        path.addArc(center: center, radius: ri, startAngle: ang(i + 1, ri, 1), endAngle: ang(i, ri, -1), clockwise: false)
        path.closeSubpath()
        // Growing the shape by `corner` with round joins rounds every corner.
        let grown = path.copy(strokingWithWidth: corner * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        return path.union(grown, using: .winding)
    }

    /// Glass mask: a disc with a hole, so the frosted rim shows around the tiles and the hole stays clear.
    static func maskImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let path = NSBezierPath(ovalIn: NSRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            path.append(NSBezierPath(ovalIn: NSRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
    }

    private func index(at point: CGPoint) -> Int? {
        let dx = point.x - center.x, dy = point.y - center.y
        let r = hypot(dx, dy)
        guard r >= Self.inner, r <= Self.outer + 6 * Self.scale, !items.isEmpty else { return nil }
        var angle = atan2(dx, dy) * 180 / .pi   // clockwise from top
        if angle < 0 { angle += 360 }
        return min(Int(angle / step), items.count - 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !items.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let n = items.count

        // Rim: soft tint and bright edges on the glass ring.
        NSColor.clear.setFill()
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - Self.outer, y: center.y - Self.outer,
                                               width: Self.outer * 2, height: Self.outer * 2))
        ring.append(NSBezierPath(ovalIn: NSRect(x: center.x - Self.inner, y: center.y - Self.inner,
                                                width: Self.inner * 2, height: Self.inner * 2)))
        ring.windingRule = .evenOdd
        ring.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        for r in [Self.outer - 0.5, Self.inner + 0.5] {
            let edge = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            edge.lineWidth = 1
            edge.stroke()
        }

        // Tiles.
        for i in items.indices {
            let path = Self.tile(i, of: n, center: center)
            // Button tile: whitish and mostly opaque, so the glass ring behind reads as the glass.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(NSColor.white.withAlphaComponent(i == hovered ? 0.9 : 0.5).cgColor)
            ctx.fill(bounds)
            let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                NSColor.white.withAlphaComponent(i == hovered ? 0.5 : 0.35).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
            let box = path.boundingBox
            ctx.drawLinearGradient(sheen, start: CGPoint(x: box.midX, y: box.maxY),
                                   end: CGPoint(x: box.midX, y: box.midY), options: [])
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(i == hovered ? 0.9 : 0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }

        // Labels: bold, centered, wrapped onto two lines when long.
        let mid = (Self.inner + Self.outer) / 2 + 2 * Self.scale
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        for (i, item) in items.enumerated() {
            let theta = (90 - (CGFloat(i) + 0.5) * (360 / CGFloat(n))) * .pi / 180
            let p = CGPoint(x: center.x + cos(theta) * mid, y: center.y + sin(theta) * mid)
            var text = item.label
            if text.count > 9, let space = text.firstIndex(of: " ") { text.replaceSubrange(space...space, with: "\n") }
            let attr = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: (n > 8 ? 14 : 16) * Self.scale, weight: .bold),
                .foregroundColor: NSColor.black.withAlphaComponent(0.88), .paragraphStyle: style])
            let size = attr.size()
            attr.draw(in: NSRect(x: p.x - 60 * Self.scale, y: p.y - size.height / 2, width: 120 * Self.scale, height: size.height))
        }

        // Center: size pill only; the hole stays clear.
        let pillText = NSAttributedString(string: hovered.map { items[$0].label } ?? sizeText, attributes: [
            .font: NSFont.systemFont(ofSize: 15 * Self.scale, weight: .semibold), .foregroundColor: NSColor.black.withAlphaComponent(0.85)])
        let ps = pillText.size()
        let sc = Self.scale
        let pill = NSRect(x: center.x - ps.width / 2 - 14 * sc, y: center.y - 16 * sc, width: ps.width + 28 * sc, height: 32 * sc)
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: 16 * sc, yRadius: 16 * sc)
        NSColor.white.withAlphaComponent(0.93).setFill()
        pillPath.fill()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        pillPath.lineWidth = 1
        pillPath.stroke()
        pillText.draw(at: CGPoint(x: pill.midX - ps.width / 2, y: pill.midY - ps.height / 2))
    }

    // MARK: NSDraggingDestination

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovered = index(at: convert(sender.draggingLocation, from: nil))
        return hovered == nil ? [] : .copy
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let i = index(at: convert(sender.draggingLocation, from: nil)),
              let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }
        onDrop?(i, urls)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { hovered = nil }
}

/// Borderless, non-activating panel so the Finder drag keeps focus.
final class WheelPanel: NSPanel {
    private let effect = NSVisualEffectView()
    private var glass: NSView?   // NSGlassEffectView on macOS 26+
    let wheel: WheelView
    static var side: CGFloat { (WheelView.outer + 12 * WheelView.scale) * 2 }

    init() {
        let size = NSSize(width: Self.side, height: Self.side)
        wheel = WheelView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        effect.frame = root.bounds
        effect.autoresizingMask = [.width, .height]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView(frame: root.bounds)
            g.autoresizingMask = [.width, .height]
            g.style = .clear
            g.cornerRadius = Self.side / 2
            g.wantsLayer = true
            root.addSubview(g)
            glass = g
        } else {
            root.addSubview(effect)
        }
        wheel.frame = root.bounds
        wheel.autoresizingMask = [.width, .height]
        root.addSubview(wheel)
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(items: [WheelItem], title: String, urls: [URL], at point: NSPoint) {
        setContentSize(NSSize(width: Self.side, height: Self.side))
        if #available(macOS 26.0, *) { (glass as? NSGlassEffectView)?.cornerRadius = Self.side / 2 }
        wheel.items = items
        wheel.title = title
        wheel.fileCount = urls.count
        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        wheel.sizeText = urls.count > 1 ? "\(urls.count) files" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        effect.maskImage = WheelView.maskImage(size: NSSize(width: Self.side, height: Self.side))
        if let glass {
            // Cut the ring (disc minus hole) out of the glass.
            let c = CGPoint(x: Self.side / 2, y: Self.side / 2)
            let ring = CGMutablePath()
            ring.addEllipse(in: CGRect(x: c.x - WheelView.outer, y: c.y - WheelView.outer, width: WheelView.outer * 2, height: WheelView.outer * 2))
            ring.addEllipse(in: CGRect(x: c.x - WheelView.inner, y: c.y - WheelView.inner, width: WheelView.inner * 2, height: WheelView.inner * 2))
            let mask = CAShapeLayer()
            mask.frame = glass.bounds
            mask.path = ring
            mask.fillRule = .evenOdd
            glass.layer?.mask = mask
        }
        var origin = NSPoint(x: point.x - Self.side / 2, y: point.y - Self.side / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - Self.side)
            origin.y = min(max(origin.y, f.minY), f.maxY - Self.side)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
    }
}
