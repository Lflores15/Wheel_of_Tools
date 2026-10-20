import AppKit

enum WheelMode { case convert, tools }

/// Detects "a Finder file drag is in progress" by polling — no Accessibility permission needed.
/// A drag counts when the left button is down, the drag pasteboard changed since the press,
/// and it holds file URLs. Shift opens the convert wheel; Control opens the tools wheel.
@MainActor
final class DragWatcher {
    var onShow: ((WheelMode, [URL], NSPoint) -> Void)?
    var onHide: (() -> Void)?

    private var timer: Timer?
    private var wasDown = false
    private var pressChange = 0
    private var pressPoint = NSPoint.zero
    private var urls: [URL] = []
    private var checkedPasteboard = false
    private var shownMode: WheelMode?
    private var hideWork: DispatchWorkItem?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let pb = NSPasteboard(name: .drag)
        if down && !wasDown {
            pressChange = pb.changeCount
            pressPoint = NSEvent.mouseLocation
            urls = []
            checkedPasteboard = false
        }
        if down {
            if urls.isEmpty, !checkedPasteboard, pb.changeCount != pressChange,
               hypot(NSEvent.mouseLocation.x - pressPoint.x, NSEvent.mouseLocation.y - pressPoint.y) > 5 {
                checkedPasteboard = true
                urls = (pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            }
            if !urls.isEmpty { update() }
        } else if wasDown {
            if shownMode != nil {
                // Give the drop a moment to land before the wheel disappears.
                let work = DispatchWorkItem { [weak self] in self?.hide() }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
            urls = []
        }
        wasDown = down
    }

    private func update() {
        let flags = NSEvent.modifierFlags
        let wanted: WheelMode? = (flags.contains(.control) || flags.isSuperset(of: [.option, .shift])) ? .tools : (flags.contains(.shift) ? .convert : nil)
        guard wanted != shownMode else { return }
        hideWork?.cancel()
        if let wanted {
            let first = shownMode == nil
            shownMode = wanted
            onShow?(wanted, urls, first ? NSEvent.mouseLocation : lastCenter)
            if first { lastCenter = NSEvent.mouseLocation }
        } else {
            hide()
        }
    }
    private var lastCenter = NSPoint.zero

    private func hide() {
        shownMode = nil
        onHide?()
    }
}
