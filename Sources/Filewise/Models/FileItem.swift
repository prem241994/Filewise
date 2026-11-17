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
    var displaySize: String { kind == "app" && size == 0 ? "Unavailable" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

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

    /// Why this file is a cleanup candidate, in display order.
    var cleanupReasons: [CleanupReason] {
        var reasons: [CleanupReason] = []
        if duplicate { reasons.append(.duplicate) }
        if isLarge { reasons.append(.large) }
        if isOldScreenshot { reasons.append(.oldScreenshot) }
        if isForgottenDownload { reasons.append(.forgottenDownload) }
        return reasons
    }
}

enum CleanupReason: CaseIterable {
    case duplicate, large, oldScreenshot, forgottenDownload

    var label: String {
        switch self {
        case .duplicate: "Duplicate"
        case .large: "Large"
        case .oldScreenshot: "Old screenshot"
        case .forgottenDownload: "Old download"
        }
    }

    var explanation: String {
        switch self {
        case .duplicate: "Another file in this folder has identical contents."
        case .large: "Larger than 100 MB."
        case .oldScreenshot: "A screenshot last modified more than 30 days ago."
        case .forgottenDownload: "In Downloads and not modified for more than 30 days."
        }
    }

    var symbol: String {
        switch self {
        case .duplicate: "square.on.square"
        case .large: "externaldrive"
        case .oldScreenshot: "camera.viewfinder"
        case .forgottenDownload: "arrow.down.circle"
        }
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
