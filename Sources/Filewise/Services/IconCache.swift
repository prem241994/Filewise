import AppKit
import UniformTypeIdentifiers

/// Fast in-memory cache for macOS file type icons.
/// Avoids hitting disk/filesystem APIs on the main thread during list scrolling.
final class IconCache {
    static let shared = IconCache()
    private var cache = [String: NSImage]()
    private let lock = NSLock()

    private init() {}

    func icon(for file: FileItem) -> NSImage {
        let key = file.kind.isEmpty ? "default_file" : file.kind
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image: NSImage
        if let utType = UTType(filenameExtension: file.kind) {
            image = NSWorkspace.shared.icon(for: utType)
        } else {
            image = NSWorkspace.shared.icon(for: .item)
        }
        image.size = NSSize(width: 29, height: 29)
        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }
}
