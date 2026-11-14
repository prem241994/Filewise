import Foundation

struct FileItem: Identifiable {
    let url: URL
    let size: Int64
    let modified: Date
    let changed: Date?
    var duplicate: Bool
    var hash: Data?
    var downloadSource: String?
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var kind: String { url.pathExtension.lowercased() }
    var displaySize: String { kind == "app" ? "Not calculated" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    var libraryCategory: String? {
        switch kind {
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "tif", "tiff", "svg", "raw": "Images"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": "Videos"
        case "mp3", "m4a", "wav", "flac", "aiff", "aac": "Music"
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "md", "csv", "xls", "xlsx", "ppt", "pptx", "key", "numbers": "Documents"
        case "zip", "tar", "gz", "7z", "rar", "dmg", "iso": "Archives"
        case "app": "Apps"
        default: nil
        }
    }

    var isImage: Bool {
        switch kind {
        case "png", "jpg", "jpeg", "heic", "webp", "tif", "tiff", "gif", "svg", "raw":
            return true
        default:
            return false
        }
    }

    var isScreenshot: Bool {
        guard isImage else { return false }
        let lower = name.lowercased()
        return lower.contains("screenshot")
            || lower.contains("screen shot")
            || lower.contains("screen_shot")
            || lower.hasPrefix("clean shot")
            || lower.hasPrefix("cleanshot")
    }

    var isDownload: Bool { url.pathComponents.contains("Downloads") }
    var isLarge: Bool { size >= 100_000_000 }
    var isOldScreenshot: Bool {
        isScreenshot && modified < (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
    }
    var isForgottenDownload: Bool {
        kind != "app" && isDownload && modified < (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
    }
}

struct TrashedRecord: Identifiable {
    var id: String { originalPath }
    let originalPath: String
    let trashPath: String
    let name: String
    let size: Int64
    let trashedAt: Date
    let batchId: String
}
