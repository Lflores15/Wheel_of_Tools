import Foundation

public struct ToolError: Error, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private final class DataBox: @unchecked Sendable { var data = Data() }

/// Runs command-line backends. GUI apps don't inherit the shell PATH, so look in the usual places.
public enum Shell {
    public static func find(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin"] {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    @discardableResult
    public static func run(_ tool: String, _ args: [String]) throws -> String {
        guard let path = tool.hasPrefix("/") ? tool : find(tool) else {
            throw ToolError("\(tool) is not installed (try: brew install \(tool))")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()

        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        let stdout = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = stderr.split(separator: "\n").suffix(3).joined(separator: "\n")
            throw ToolError("\((path as NSString).lastPathComponent) failed: \(tail.isEmpty ? "exit \(process.terminationStatus)" : tail)")
        }
        return stdout
    }
}

/// `name.ext`, or `name 2.ext`, `name 3.ext`... — never overwrites anything.
public func uniqueURL(dir: URL, base: String, ext: String) -> URL {
    let fm = FileManager.default
    func make(_ n: Int) -> URL {
        let name = n == 1 ? base : "\(base) \(n)"
        return dir.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
    }
    var n = 1
    while fm.fileExists(atPath: make(n).path) { n += 1 }
    return make(n)
}

/// ImageMagick input spec with the coder forced from the file extension, so a file whose contents
/// pretend to be another format (MVG, MSL, SVG with external refs...) is never auto-detected as one.
public func magickInput(_ url: URL, firstFrame: Bool = true) -> String {
    let coders = ["jpg": "jpeg", "png": "png", "heic": "heic", "webp": "webp", "tiff": "tiff",
                  "bmp": "bmp", "gif": "gif", "avif": "avif", "svg": "msvg"]
    let prefix = coders[normalizedExt(url)].map { $0 + ":" } ?? ""
    return prefix + url.path + (firstFrame ? "[0]" : "")
}
