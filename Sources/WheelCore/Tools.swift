import Foundation
import PDFKit
import Vision

public enum Tool: String, CaseIterable, Sendable {
    case compress, metadata, stripMetadata, qr, merge, split, snapshot, normalize
    case crop, adjust, annotate, background, redact

    public var label: String {
        switch self {
        case .compress: "Compress"
        case .metadata: "Metadata"
        case .stripMetadata: "Remove Metadata"
        case .qr: "Read QR"
        case .merge: "Merge PDF"
        case .split: "Split PDF"
        case .snapshot: "Snapshot"
        case .normalize: "Normalize"
        case .crop: "Crop"
        case .adjust: "Edit"
        case .annotate: "Annotate"
        case .background: "Background"
        case .redact: "Redact"
        }
    }

    public var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .metadata: "info.circle"
        case .stripMetadata: "eraser"
        case .qr: "qrcode.viewfinder"
        case .merge: "doc.on.doc"
        case .split: "scissors"
        case .snapshot: "camera"
        case .normalize: "waveform"
        case .crop: "crop"
        case .adjust: "slider.horizontal.3"
        case .annotate: "pencil.tip.crop.circle"
        case .background: "photo.on.rectangle"
        case .redact: "rectangle.fill"
        }
    }

    /// Tools that need the interactive image editor rather than running headlessly.
    public var isEditor: Bool { [.crop, .adjust, .annotate, .background, .redact].contains(self) }

    public static func available(for url: URL, count: Int) -> [Tool] {
        switch FileKind.detect(url) {
        case .image:
            var list: [Tool] = [.compress, .crop, .adjust, .annotate, .background, .redact, .metadata, .stripMetadata, .qr]
            if count > 1 { list.append(.merge) }
            return list
        case .pdf: return [.compress, .merge, .split, .metadata, .stripMetadata]
        case .video: return [.compress, .snapshot, .metadata, .stripMetadata]
        case .audio: return [.compress, .normalize, .metadata, .stripMetadata]
        case .document, .spreadsheet, .presentation:
            return ["docx", "xlsx", "pptx"].contains(normalizedExt(url)) ? [.metadata, .stripMetadata] : [.metadata]
        default: return [.metadata]
        }
    }
}

public struct JobResult: Sendable {
    public var outputs: [URL] = []
    public var text: String?
    public init(outputs: [URL] = [], text: String? = nil) { self.outputs = outputs; self.text = text }
}

public enum Tools {
    /// Runs a non-interactive tool over the dropped files.
    public static func run(_ tool: Tool, on urls: [URL]) throws -> JobResult {
        guard let first = urls.first else { return JobResult() }
        switch tool {
        case .merge:
            return JobResult(outputs: [try merge(urls)])
        case .metadata:
            return JobResult(text: try urls.map { try metadata($0) }.joined(separator: "\n\n"))
        case .qr:
            let found = try urls.flatMap { try readQR($0) }
            return JobResult(text: found.isEmpty ? "No QR code found." : found.joined(separator: "\n"))
        case .split:
            return JobResult(outputs: try urls.flatMap { try split($0) })
        case .compress: return JobResult(outputs: try urls.map(compress))
        case .stripMetadata: return JobResult(outputs: try urls.map(stripMetadata))
        case .snapshot: return JobResult(outputs: try urls.map(snapshot))
        case .normalize: return JobResult(outputs: try urls.map(normalize))
        case .crop, .adjust, .annotate, .background, .redact:
            throw ToolError("\(tool.label) needs the editor (\(first.lastPathComponent))")
        }
    }

    static func dest(_ src: URL, _ suffix: String, ext: String? = nil) -> URL {
        uniqueURL(dir: src.deletingLastPathComponent(),
                  base: src.deletingPathExtension().lastPathComponent + " " + suffix,
                  ext: ext ?? src.pathExtension)
    }

    // MARK: Compress

    public static func compress(_ src: URL) throws -> URL {
        switch FileKind.detect(src) {
        case .image:
            let out = dest(src, "compressed")
            var args = [magickInput(src), "-auto-orient"]
            switch normalizedExt(src) {
            case "png": args += ["-define", "png:compression-level=9", "-colors", "256", "-strip"]
            case "gif", "bmp", "svg": break
            default: args += ["-quality", "70", "-sampling-factor", "4:2:0"]
            }
            try Shell.run("magick", args + [out.path])
            return out
        case .pdf:
            guard let doc = PDFDocument(url: src) else { throw ToolError("Could not open PDF") }
            let out = dest(src, "compressed")
            var images: [CGImage] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i), let cg = renderPage(page, scale: 1.5) else { continue }
                // Recompress each page as a mid-quality JPEG before rebuilding the PDF.
                let rep = NSBitmapImageRep(cgImage: cg)
                guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.55]),
                      let small = NSBitmapImageRep(data: jpeg)?.cgImage else { continue }
                images.append(small)
            }
            try pdfFromImages(images, to: out)
            return out
        case .video:
            let out = dest(src, "compressed", ext: "mp4")
            try Shell.run("ffmpeg", ["-y", "-loglevel", "error", "-protocol_whitelist", "file", "-i", src.path, "-c:v", "libx264", "-crf", "28",
                                     "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
                                     "-movflags", "+faststart", out.path])
            return out
        case .audio:
            let kept = ["mp3", "m4a", "opus"]
            let ext = kept.contains(normalizedExt(src)) ? normalizedExt(src) : "m4a"
            let out = dest(src, "compressed", ext: ext)
            let codec: [String]
            switch ext {
            case "mp3": codec = ["-c:a", "libmp3lame", "-b:a", "96k"]
            case "opus": codec = ["-c:a", "libopus", "-b:a", "64k"]
            default: codec = ["-c:a", "aac", "-b:a", "96k"]
            }
            try Shell.run("ffmpeg", ["-y", "-loglevel", "error", "-protocol_whitelist", "file", "-i", src.path, "-vn"] + codec + [out.path])
            return out
        default:
            throw ToolError("Can't compress this kind of file")
        }
    }

    // MARK: Metadata

    public static func metadata(_ src: URL) throws -> String {
        let raw = try Shell.run("exiftool", ["-G1", "-s", "-a", src.path])
        let lines = raw.split(separator: "\n").filter { !$0.hasPrefix("[ExifTool]") && !$0.hasPrefix("[System]") && !$0.hasPrefix("[File]") }
        return "\(src.lastPathComponent)\n" + (lines.isEmpty ? "(no metadata)" : lines.joined(separator: "\n"))
    }

    public static func stripMetadata(_ src: URL) throws -> URL {
        let out = dest(src, "no metadata")
        switch FileKind.detect(src) {
        case .video, .audio:
            try Shell.run("ffmpeg", ["-y", "-loglevel", "error", "-protocol_whitelist", "file", "-i", src.path, "-map", "0", "-map_metadata", "-1",
                                     "-map_chapters", "-1", "-c", "copy", out.path])
        case .pdf:
            guard let old = PDFDocument(url: src) else { throw ToolError("Could not open PDF") }
            let fresh = PDFDocument()
            for i in 0..<old.pageCount {
                if let page = old.page(at: i)?.copy() as? PDFPage { fresh.insert(page, at: i) }
            }
            fresh.documentAttributes = [:]
            guard fresh.write(to: out) else { throw ToolError("Could not write PDF") }
        default:
            // Keep only orientation so photos don't turn sideways.
            try Shell.run("exiftool", ["-all=", "-tagsfromfile", "@", "-Orientation", "-o", out.path, src.path])
        }
        return out
    }

    // MARK: PDF

    public static func merge(_ urls: [URL]) throws -> URL {
        let combined = PDFDocument()
        for url in urls {
            if FileKind.detect(url) == .pdf, let doc = PDFDocument(url: url) {
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i)?.copy() as? PDFPage { combined.insert(page, at: combined.pageCount) }
                }
            } else if FileKind.detect(url) == .image, let cg = loadCGImage(url),
                      let page = PDFPage(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))) {
                combined.insert(page, at: combined.pageCount)
            }
        }
        guard combined.pageCount > 0, let first = urls.first else { throw ToolError("Nothing to merge") }
        let out = uniqueURL(dir: first.deletingLastPathComponent(), base: "Merged", ext: "pdf")
        guard combined.write(to: out) else { throw ToolError("Could not write PDF") }
        return out
    }

    public static func split(_ src: URL) throws -> [URL] {
        guard let doc = PDFDocument(url: src) else { throw ToolError("Could not open PDF") }
        var outs: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let out = dest(src, "page \(i + 1)")
            if single.write(to: out) { outs.append(out) }
        }
        return outs
    }

    // MARK: Video / audio

    public static func snapshot(_ src: URL) throws -> URL {
        let duration = Double(try Shell.run("ffprobe", ["-v", "error", "-show_entries", "format=duration",
                                                        "-of", "default=nw=1:nk=1", src.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let out = dest(src, "snapshot", ext: "png")
        try Shell.run("ffmpeg", ["-y", "-loglevel", "error", "-protocol_whitelist", "file", "-ss", String(duration / 2), "-i", src.path,
                                 "-frames:v", "1", out.path])
        return out
    }

    public static func normalize(_ src: URL) throws -> URL {
        let out = dest(src, "normalized")
        try Shell.run("ffmpeg", ["-y", "-loglevel", "error", "-protocol_whitelist", "file", "-i", src.path, "-vn",
                                 "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", out.path])
        return out
    }

    // MARK: QR

    public static func readQR(_ src: URL) throws -> [String] {
        guard let cg = loadCGImage(src) else { throw ToolError("Could not read \(src.lastPathComponent)") }
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: cg).perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }
}
