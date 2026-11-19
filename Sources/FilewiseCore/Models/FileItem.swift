import Foundation

public struct FileItem: Identifiable, Sendable {
    public let url: URL
    public let size: Int64
    public let modified: Date
    public let changed: Date?
    public var duplicate: Bool
    public var hash: Data?
    public var downloadSource: String?
    /// When the file was last opened, as recorded by macOS.
    public var lastOpened: Date?

    public init(url: URL, size: Int64, modified: Date, changed: Date?,
                duplicate: Bool, hash: Data?, downloadSource: String?, lastOpened: Date? = nil) {
        self.url = url
        self.size = size
        self.modified = modified
        self.changed = changed
        self.duplicate = duplicate
        self.hash = hash
        self.downloadSource = downloadSource
        self.lastOpened = lastOpened
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var kind: String { url.pathExtension.lowercased() }
    public var displaySize: String { kind == "app" && size == 0 ? "Unavailable" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    public var libraryCategory: String? {
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

    public var isImage: Bool {
        switch kind {
        case "png", "jpg", "jpeg", "heic", "webp", "tif", "tiff", "gif", "svg", "raw":
            return true
        default:
            return false
        }
    }

    public var isScreenshot: Bool {
        guard isImage else { return false }
        let lower = name.lowercased()
        return lower.contains("screenshot")
            || lower.contains("screen shot")
            || lower.contains("screen_shot")
            || lower.hasPrefix("clean shot")
            || lower.hasPrefix("cleanshot")
    }

    public var isDownload: Bool { url.pathComponents.contains("Downloads") }
    /// Shown in "By Source": files with a known download origin, plus anything
    /// in a Downloads folder.
    public var isDownloaded: Bool { downloadSource != nil || isDownload }
    public var isLarge: Bool { size >= CleanupSettings.current.largeFileBytes }
    public var isOldScreenshot: Bool {
        isScreenshot && modified < CleanupSettings.current.oldCutoff()
    }
    /// The later of the last modification and the last time it was opened.
    public var lastUsed: Date { max(modified, lastOpened ?? .distantPast) }
    public var isForgottenDownload: Bool {
        kind != "app" && isDownload && lastUsed < CleanupSettings.current.oldCutoff()
    }

    /// Why this file is a cleanup candidate, in display order.
    public var cleanupReasons: [CleanupReason] {
        var reasons: [CleanupReason] = []
        if duplicate { reasons.append(.duplicate) }
        if isLarge { reasons.append(.large) }
        if isOldScreenshot { reasons.append(.oldScreenshot) }
        if isForgottenDownload { reasons.append(.forgottenDownload) }
        return reasons
    }

    /// Whether any cleanup view suggests this file.
    public var isCleanupCandidate: Bool { duplicate || isOldScreenshot || isForgottenDownload || isLarge }
}

public enum CleanupReason: CaseIterable, Sendable {
    case duplicate, large, oldScreenshot, forgottenDownload

    public var label: String {
        switch self {
        case .duplicate: "Duplicate"
        case .large: "Large"
        case .oldScreenshot: "Old screenshot"
        case .forgottenDownload: "Old download"
        }
    }

    public var explanation: String {
        switch self {
        case .duplicate: "Another file in this folder has identical contents."
        case .large:
            "Larger than \(ByteCountFormatter.string(fromByteCount: CleanupSettings.current.largeFileBytes, countStyle: .file))."
        case .oldScreenshot:
            "A screenshot last modified more than \(CleanupSettings.current.oldAfterDays) days ago."
        case .forgottenDownload:
            "In Downloads and not opened or modified for more than \(CleanupSettings.current.oldAfterDays) days."
        }
    }

    public var symbol: String {
        switch self {
        case .duplicate: "square.on.square"
        case .large: "externaldrive"
        case .oldScreenshot: "camera.viewfinder"
        case .forgottenDownload: "arrow.down.circle"
        }
    }
}

public struct TrashedRecord: Identifiable, Sendable {
    public var id: String { originalPath }
    public let originalPath: String
    public let trashPath: String
    public let name: String
    public let size: Int64
    public let trashedAt: Date
    public let batchId: String
}

/// One Trash journal row: written with an empty `trash` path before a move,
/// then rewritten with the Trash location once the move succeeds.
public typealias TrashJournalEntry = (original: String, trash: String, name: String, size: Int64)
