import AppKit

/// "Move to Applications folder?" prompt shown when the app is launched from Downloads, a disk image, etc.
@MainActor
enum MoveToApplications {
    private static let skipKey = "dontAskToMove"

    static func offerIfNeeded() {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", !UserDefaults.standard.bool(forKey: skipKey) else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = bundle.path
        guard !path.hasPrefix("/Applications/"), !path.hasPrefix(home + "/Applications/") else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move to Applications folder?"
        alert.informativeText = "Wheel of Tools works best from your Applications folder. I can move it there for you and relaunch."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipKey) }
        guard response == .alertFirstButtonReturn else { return }

        do { try move(from: bundle) }
        catch {
            let failed = NSAlert()
            failed.messageText = "Couldn't move the app"
            failed.informativeText = error.localizedDescription + "\n\nYou can drag Wheel of Tools into your Applications folder yourself."
            failed.runModal()
        }
    }

    private static func move(from source: URL) throws {
        let fm = FileManager.default
        let name = source.lastPathComponent
        // /Applications if we may write there (admin users), otherwise ~/Applications.
        var dir = URL(fileURLWithPath: "/Applications")
        if !fm.isWritableFile(atPath: dir.path) {
            dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let dest = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
        try fm.copyItem(at: source, to: dest)

        // Downloaded apps carry a quarantine flag; the copy is the one the user chose to keep.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", dest.path]
        try? xattr.run()
        xattr.waitUntilExit()

        // A translocated path is a read-only mirror of the download; only trash real locations.
        if !source.path.contains("/AppTranslocation/") { try? fm.trashItem(at: source, resultingItemURL: nil) }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
