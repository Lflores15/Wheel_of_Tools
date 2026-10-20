import Foundation
import PDFKit

public enum Converter {
    /// Target formats offered for a dropped file, in wheel order.
    public static func formats(for url: URL) -> [String] {
        let ext = normalizedExt(url)
        let list: [String]
        switch FileKind.detect(url) {
        case .image: list = ["jpg", "png", "heic", "webp", "tiff", "avif", "bmp", "gif", "pdf"]
        case .pdf: list = ["png", "jpg", "txt", "docx"]
        case .video: list = ["mp4", "mov", "mkv", "avi", "wmv", "webm", "gif", "mp3"]
        case .audio: list = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"]
        case .text: list = ["pdf", "txt", "docx", "pages", "zip"]
        case .document: list = ["pdf", "docx", "pages", "rtf", "txt"]
        case .spreadsheet: list = ["pdf", "xlsx", "numbers", "csv"]
        case .presentation: list = ["pdf", "pptx", "key", "png"]
        case .subtitle: list = ["srt", "vtt", "zip"]
        case .other: list = ["zip", "tar", "gz"]
        }
        return list.filter { $0 != ext }
    }

    public static func convert(_ src: URL, to target: String) throws -> [URL] {
        let dir = src.deletingLastPathComponent()
        let stem = src.deletingPathExtension().lastPathComponent
        let same = normalizedExt(src) == target
        let base = same ? stem + " converted" : stem
        func out(_ ext: String = target, suffix: String = "") -> URL {
            uniqueURL(dir: dir, base: base + suffix, ext: ext)
        }

        if ["zip", "tar", "gz"].contains(target) { return [try archive(src, as: target, to: out())] }

        switch FileKind.detect(src) {
        case .image:
            if target == "pdf" {
                guard let cg = loadCGImage(src) else { throw ToolError("Could not read \(src.lastPathComponent)") }
                let dest = out()
                try pdfFromImages([cg], to: dest)
                return [dest]
            }
            let dest = out()
            try magickConvert(src, to: dest, target: target)
            return [dest]

        case .pdf:
            guard let doc = PDFDocument(url: src) else { throw ToolError("Could not open PDF") }
            switch target {
            case "txt":
                let dest = out()
                try (doc.string ?? "").write(to: dest, atomically: true, encoding: .utf8)
                return [dest]
            case "docx":
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
                defer { try? FileManager.default.removeItem(at: tmp) }
                try (doc.string ?? "").write(to: tmp, atomically: true, encoding: .utf8)
                let dest = out()
                try Shell.run("textutil", ["-convert", "docx", tmp.path, "-output", dest.path])
                return [dest]
            default:
                var results: [URL] = []
                for i in 0..<doc.pageCount {
                    guard let page = doc.page(at: i), let cg = renderPage(page) else { continue }
                    let dest = out(suffix: doc.pageCount > 1 ? " page \(i + 1)" : "")
                    if target == "png" || target == "jpg" {
                        try writeImage(cg, to: dest)
                    } else {
                        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        try writeImage(cg, to: tmp)
                        try magickConvert(tmp, to: dest, target: target)
                    }
                    results.append(dest)
                }
                if results.isEmpty { throw ToolError("PDF has no pages") }
                return results
            }

        case .video, .audio, .subtitle:
            let dest = out()
            try Shell.run("ffmpeg", ["-y", "-loglevel", "error", "-protocol_whitelist", "file", "-i", src.path] + ffmpegArgs(target) + [dest.path])
            return [dest]

        case .document, .spreadsheet, .presentation:
            return [try Office.convert(src, to: target, dest: out(target == "png" ? "" : target, suffix: target == "png" ? " slides" : ""))]

        case .text:
            if target == "pages" { return [try Office.convert(src, to: target, dest: out())] }
            let dest = out()
            let ext = normalizedExt(src)
            if target == "pdf" {
                try textToPDF(try plainText(of: src), to: dest)
            } else if ext == "md" {
                try Shell.run("pandoc", ["--sandbox", src.path, "-o", dest.path] + (target == "txt" ? ["-t", "plain"] : []))
            } else {
                try Shell.run("textutil", ["-convert", target, src.path, "-output", dest.path])
            }
            return [dest]

        case .other:
            throw ToolError("Can't convert .\(src.pathExtension) to \(target)")
        }
    }

    static func plainText(of url: URL) throws -> String {
        switch normalizedExt(url) {
        case "txt", "md": return try String(contentsOf: url, encoding: .utf8)
        default: return try Shell.run("textutil", ["-convert", "txt", "-stdout", url.path])
        }
    }

    static func magickConvert(_ src: URL, to dest: URL, target: String) throws {
        var args = [magickInput(src), "-auto-orient"]
        if ["jpg", "bmp"].contains(target) { args += ["-background", "white", "-alpha", "remove", "-alpha", "off"] }
        if ["jpg", "webp", "avif", "heic"].contains(target) { args += ["-quality", "90"] }
        try Shell.run("magick", args + [dest.path])
    }

    static func ffmpegArgs(_ target: String) -> [String] {
        switch target {
        case "mp4": return ["-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"]
        case "mov", "mkv": return ["-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac"]
        case "avi": return ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "libmp3lame"]
        case "wmv": return ["-c:v", "wmv2", "-b:v", "4M", "-c:a", "wmav2"]
        case "webm": return ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-c:a", "libopus"]
        case "gif": return ["-vf", "fps=12,scale=480:-1:flags=lanczos", "-an"]
        case "mp3": return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a": return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "wav": return ["-vn", "-c:a", "pcm_s16le"]
        case "flac": return ["-vn", "-c:a", "flac"]
        case "ogg": return ["-vn", "-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-b:a", "160k"]
        case "opus": return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case "aiff": return ["-vn", "-c:a", "pcm_s16be"]
        default: return []
        }
    }

    static func archive(_ src: URL, as kind: String, to dest: URL) throws -> URL {
        switch kind {
        case "zip": try Shell.run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", src.path, dest.path])
        case "tar": try Shell.run("tar", ["-C", src.deletingLastPathComponent().path, "-cf", dest.path, "./" + src.lastPathComponent])
        default: try Shell.run("/bin/sh", ["-c", "gzip -c \"$1\" > \"$2\"", "sh", src.path, dest.path])
        }
        return dest
    }
}
