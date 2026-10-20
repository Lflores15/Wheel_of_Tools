import Foundation

public enum FileKind: Sendable {
    case image, pdf, video, audio, text, subtitle, document, spreadsheet, presentation, other

    public static func detect(_ url: URL) -> FileKind {
        switch normalizedExt(url) {
        case "jpg", "png", "heic", "webp", "tiff", "bmp", "gif", "avif", "svg": return .image
        case "pdf": return .pdf
        case "mp4", "mov", "mkv", "avi", "wmv", "webm", "m4v": return .video
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aac": return .audio
        case "txt", "md", "html": return .text
        case "pages", "docx", "doc", "rtf", "odt": return .document
        case "numbers", "xlsx", "xls", "csv", "tsv": return .spreadsheet
        case "key", "pptx", "ppt", "odp": return .presentation
        case "srt", "vtt": return .subtitle
        default: return .other
        }
    }
}

public func normalizedExt(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpeg", "jpe": return "jpg"
    case "tif": return "tiff"
    case "heif": return "heic"
    case "aif": return "aiff"
    case "gz": return "gz"
    case let e: return e
    }
}
