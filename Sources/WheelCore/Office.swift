import Foundation

/// Word / Excel / PowerPoint / Pages / Numbers / Keynote conversion by driving the installed
/// Apple iWork apps with AppleScript. They open Microsoft formats and export to them too.
public enum Office {
    public static func convert(_ src: URL, to target: String, dest: URL) throws -> URL {
        let kind = FileKind.detect(src)
        if target == "rtf" {   // Pages has no RTF export; textutil reads Word formats natively.
            var input = src
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
            defer { try? FileManager.default.removeItem(at: tmp) }
            if !["docx", "doc", "odt"].contains(normalizedExt(src)) {
                input = try convert(src, to: "docx", dest: tmp)
            }
            try Shell.run("textutil", ["-convert", "rtf", input.path, "-output", dest.path])
            return dest
        }
        let (app, line): (String, String)
        switch kind {
        case .document, .text:
            app = "Pages"
            switch target {
            case "pages": line = "save d in outP"
            case "pdf": line = "export d to outP as PDF"
            case "docx", "doc": line = "export d to outP as Microsoft Word"
            case "rtf": line = "export d to outP as RTF"
            case "txt": line = "export d to outP as unformatted text"
            default: throw ToolError("Can't convert a document to \(target)")
            }
        case .spreadsheet:
            app = "Numbers"
            switch target {
            case "numbers": line = "save d in outP"
            case "pdf": line = "export d to outP as PDF"
            case "xlsx": line = "export d to outP as Microsoft Excel"
            case "csv": line = "export d to outP as CSV"
            default: throw ToolError("Can't convert a spreadsheet to \(target)")
            }
        case .presentation:
            app = "Keynote"
            switch target {
            case "key": line = "save d in outP"
            case "pdf": line = "export d to outP as PDF"
            case "pptx": line = "export d to outP as Microsoft PowerPoint"
            case "png": line = "export d to outP as slide images with properties {image format:PNG}"
            default: throw ToolError("Can't convert a presentation to \(target)")
            }
        default: throw ToolError("Not an office file")
        }
        if !FileManager.default.fileExists(atPath: "/Applications/\(app).app") {
            throw ToolError("\(app) is required for this conversion but isn't installed")
        }
        let script = """
        on run argv
          set inP to POSIX file (item 1 of argv)
          set outP to POSIX file (item 2 of argv)
          tell application "\(app)"
            set d to open inP
            try
              \(line)
            on error e
              close d saving no
              error e
            end try
            close d saving no
          end tell
        end run
        """
        do {
            try Shell.run("osascript", ["-e", script, src.path, dest.path])
        } catch let error as ToolError {
            throw ToolError(error.message.contains("-1743") || error.message.contains("not allowed")
                ? "Allow Wheel of Tools to control \(app) in System Settings → Privacy & Security → Automation."
                : error.message)
        }
        guard FileManager.default.fileExists(atPath: dest.path) else { throw ToolError("\(app) didn't produce a file") }
        return dest
    }
}
