import AppKit
import SwiftUI
import WheelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let panel = WheelPanel()
    private let watcher = DragWatcher()
    private var statusItem: NSStatusItem!
    private var currentMode: WheelMode = .convert
    private var currentURLs: [URL] = []
    private var currentActions: [Action] = []

    enum Action {
        case convert(String)
        case tool(Tool)
    }

    private var activity: NSObjectProtocol?
    private var settingsWindow: NSWindow?

    /// Settings window, so the app is reachable without the menu-bar icon.
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Wheel of Tools"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(onPreview: { [weak self] in self?.preview(.convert) }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Launching the app again (Finder, Spotlight, Dock) opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar app with no windows gets App Nap'd, which throttles the drag-polling timer.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical], reason: "Watching for file drags")
        let saved = UserDefaults.standard.double(forKey: "wheelScale")
        if saved > 0 { WheelView.scale = CGFloat(saved) }
        setUpMenu()
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            DispatchQueue.main.async { self.openSettings() }
        }
        panel.wheel.onDrop = { [weak self] index, urls in self?.drop(index: index, urls: urls) }
        watcher.onShow = { [weak self] mode, urls, point in self?.show(mode, urls: urls, at: point) }
        watcher.onHide = { [weak self] in self?.panel.orderOut(nil) }
        watcher.start()
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["WOT_SELFTEST"] { runSelfTest(dir: dir) }
        if let path = ProcessInfo.processInfo.environment["WOT_RENDER"] {
            // Debug: draw the wheel into a PNG (no screen-recording permission needed), then quit.
            show(.convert, urls: [URL(fileURLWithPath: ProcessInfo.processInfo.environment["WOT_FILE"] ?? "/x/a.jpg")], at: .zero)
            let v = panel.wheel
            v.title = "Tools"
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
        if let name = ProcessInfo.processInfo.environment["WOT_PREVIEW"] { preview(name == "tools" ? .tools : .convert) }
        #endif
    }

    // MARK: Menu bar

    private func setUpMenu() {
        statusItem = NSStatusItem.systemStatusBarItem()
        statusItem.button?.image = NSImage(systemSymbolName: "dial.medium", accessibilityDescription: "Wheel of Tools")
            ?? NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Wheel of Tools")
        let menu = NSMenu()
        for line in ["Wheel of Tools", "Drag a file, then hold ⇧ Shift to convert", "or hold ⌃ Control (or ⌥⇧) for tools"] {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if !Dependencies.missing().isEmpty {
            let warn = NSMenuItem(title: "⚠︎ Some tools are missing — see Settings", action: #selector(openSettings), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let sizeItem = NSMenuItem(title: "Wheel Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (name, value) in Self.sizes {
            let item = NSMenuItem(title: name, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        sizeMenu.delegate = self
        menu.addItem(sizeItem)
        let preview1 = NSMenuItem(title: "Preview Convert Wheel", action: #selector(previewConvert), keyEquivalent: "")
        let preview2 = NSMenuItem(title: "Preview Tools Wheel", action: #selector(previewTools), keyEquivalent: "")
        preview1.target = self; preview2.target = self
        menu.addItem(preview1); menu.addItem(preview2)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wheel of Tools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    static let sizes: [(String, CGFloat)] = [("Small", 0.7), ("Medium-Small", 0.85), ("Medium", 1.0), ("Large", 1.25), ("Extra Large", 1.5)]

    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? CGFloat else { return }
        WheelView.scale = value
        UserDefaults.standard.set(Double(value), forKey: "wheelScale")
        preview(.convert)   // show the new size right away
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items { item.state = (item.representedObject as? CGFloat) == WheelView.scale ? .on : .off }
    }

    @objc private func previewConvert() { preview(.convert) }
    @objc private func previewTools() { preview(.tools) }
    private func preview(_ mode: WheelMode) {
        let sample = URL(fileURLWithPath: NSHomeDirectory() + "/sample.jpg")
        let center = NSPoint(x: NSScreen.main!.frame.midX, y: NSScreen.main!.frame.midY)
        show(mode, urls: [sample], at: center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.panel.orderOut(nil) }
    }

    // MARK: Wheel

    private func show(_ mode: WheelMode, urls: [URL], at point: NSPoint) {
        guard let first = urls.first else { return }
        log("show \(mode) for \(urls.count) file(s), first=\(first.lastPathComponent)")
        let kind = FileKind.detect(first)
        let same = urls.filter { FileKind.detect($0) == kind }
        currentMode = mode
        currentURLs = same
        switch mode {
        case .convert:
            let formats = Converter.formats(for: first)
            currentActions = formats.map { .convert($0) }
            panel.show(items: formats.map { WheelItem(label: $0.uppercased(), symbol: Self.symbol(forFormat: $0)) },
                       title: "Convert", urls: same, at: point)
        case .tools:
            let tools = Tool.available(for: first, count: same.count)
            currentActions = tools.map { .tool($0) }
            panel.show(items: tools.map { WheelItem(label: $0.label, symbol: $0.symbol) },
                       title: "Tools", urls: same, at: point)
        }
    }

    private static func symbol(forFormat ext: String) -> String {
        switch ext {
        case "jpg", "png": "photo"
        case "heic": "camera.fill"
        case "webp": "globe"
        case "tiff": "square.stack.3d.up"
        case "avif": "sparkles"
        case "bmp": "square.grid.3x3"
        case "gif": "play.square"
        case "svg": "scribble.variable"
        case "mp4", "mov", "mkv", "avi", "wmv", "webm": "film"
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff": "music.note"
        case "xlsx", "numbers", "csv": "tablecells"
        case "pptx", "key": "rectangle.on.rectangle"
        case "pdf": "doc.richtext"
        case "txt", "rtf": "text.alignleft"
        case "docx", "pages": "doc.text"
        case "srt", "vtt": "captions.bubble"
        case "zip", "tar", "gz": "archivebox"
        default: "doc"
        }
    }

    // MARK: Running jobs

    private func drop(index: Int, urls: [URL]) {
        log("drop on segment \(index) of \(currentActions.count): \(urls.map(\.lastPathComponent))")
        guard currentActions.indices.contains(index) else { return }
        let action = currentActions[index]
        let files = urls.filter { FileKind.detect($0) == FileKind.detect(currentURLs.first ?? $0) }
        let name = files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"

        if case .tool(let tool) = action, tool.isEditor {
            if let error = EditorWindows.open(url: files[0], mode: EditMode(rawValue: tool.rawValue)!) { alert("Wheel of Tools", error) }
            return
        }

        let progress = ProgressWindow(title: "\(Self.verb(action)) \(name)…")
        Task {
            let result = await Task.detached { () -> Result<JobResult, Error> in
                Result {
                    switch action {
                    case .convert(let ext):
                        return JobResult(outputs: try files.flatMap { try Converter.convert($0, to: ext) })
                    case .tool(let tool):
                        return try Tools.run(tool, on: files)
                    }
                }
            }.value
            progress.close()
            log("job finished: \(result)")
            switch result {
            case .failure(let error): alert("Something went wrong", error.localizedDescription)
            case .success(let job):
                if let text = job.text { alert("Result", text) }
                else if !job.outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(job.outputs) }
            }
        }
    }

    private static func verb(_ action: Action) -> String {
        switch action {
        case .convert(let ext): "Converting to \(ext.uppercased()):"
        case .tool(let tool): "\(tool.label):"
        }
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = String(message.prefix(3000))
        a.runModal()
    }
}

extension NSStatusItem {
    static func systemStatusBarItem() -> NSStatusItem { NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
