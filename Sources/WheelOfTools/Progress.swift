import AppKit

/// Small floating window shown while a job runs.
@MainActor
final class ProgressWindow {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(title: String) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 82),
                        styleMask: [.titled, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
        panel.title = "Wheel of Tools"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        label.stringValue = title
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 18, y: 42, width: 264, height: 20)
        bar.style = .bar
        bar.isIndeterminate = true
        bar.frame = NSRect(x: 18, y: 20, width: 264, height: 12)
        bar.startAnimation(nil)
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(bar)
        panel.center()
        panel.orderFrontRegardless()
    }

    func close() { bar.stopAnimation(nil); panel.close() }
}
