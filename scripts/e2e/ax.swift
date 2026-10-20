import AppKit
import ApplicationServices
// Finds an element whose title/description/value contains argv[1] in Finder; prints its center.
guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { exit(1) }
let root = AXUIElementCreateApplication(finder.processIdentifier)
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, n as CFString, &v); return v }
func search(_ e: AXUIElement, _ depth: Int) -> Bool {
    if depth > 12 { return false }
    for n in ["AXTitle", "AXDescription", "AXValue", "AXFilename"] {
        if let s = attr(e, n) as? String, s.contains(CommandLine.arguments[1]),
           let p = attr(e, "AXPosition"), let sz = attr(e, "AXSize") {
            var pt = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(sz as! AXValue, .cgSize, &size)
            if size.width > 0 { print(Int(pt.x + size.width / 2), Int(pt.y + size.height / 2), Int(size.width), Int(size.height)); return true }
        }
    }
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { if search(c, depth + 1) { return true } }
    return false
}
if !search(root, 0) { print("not found"); exit(1) }
