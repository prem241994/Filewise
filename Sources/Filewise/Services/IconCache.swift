import AppKit
import FilewiseCore
import UniformTypeIdentifiers

/// In-memory cache of file type icons, so list scrolling never waits on
/// Launch Services. Used only by views, on the main actor.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache = [String: NSImage]()

    private init() {}

    func icon(for file: FileItem) -> NSImage {
        let key = file.kind.isEmpty ? "default_file" : file.kind
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(for: UTType(filenameExtension: file.kind) ?? .item)
        image.size = NSSize(width: 29, height: 29)
        cache[key] = image
        return image
    }
}
