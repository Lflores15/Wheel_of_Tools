import Foundation

/// External programs the app calls, so the UI can say what is missing instead of failing on drop.
public struct Dependency: Sendable {
    public let name: String
    public let brewPackage: String?   // nil for apps
    public let purpose: String
    public let isInstalled: Bool
}

public enum Dependencies {
    public static func status() -> [Dependency] {
        func tool(_ exe: String, _ pkg: String, _ purpose: String) -> Dependency {
            Dependency(name: exe, brewPackage: pkg, purpose: purpose, isInstalled: Shell.find(exe) != nil)
        }
        func app(_ name: String, _ purpose: String) -> Dependency {
            Dependency(name: name, brewPackage: nil, purpose: purpose,
                       isInstalled: FileManager.default.fileExists(atPath: "/Applications/\(name).app"))
        }
        return [
            tool("ffmpeg", "ffmpeg", "video and audio conversion, compress, snapshot"),
            tool("magick", "imagemagick", "WebP / AVIF / HEIC output, image compress"),
            tool("exiftool", "exiftool", "metadata view and removal"),
            tool("pandoc", "pandoc", "Markdown to DOCX / TXT"),
            app("Pages", "Word, RTF and Pages documents"),
            app("Numbers", "Excel, CSV and Numbers spreadsheets"),
            app("Keynote", "PowerPoint and Keynote presentations"),
        ]
    }

    public static func missing() -> [Dependency] { status().filter { !$0.isInstalled } }

    /// One command that installs every missing Homebrew package, or nil if none are missing.
    public static func installCommand() -> String? {
        let packages = missing().compactMap(\.brewPackage)
        return packages.isEmpty ? nil : "brew install " + packages.joined(separator: " ")
    }
}
