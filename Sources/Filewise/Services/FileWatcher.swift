import CoreServices
import Foundation

/// Watches a selected folder and its descendants for filesystem changes.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let rootPrefixes: [String]
    private let indexPath = FileIndex.databaseDirectory.path

    init?(root: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        // FSEvents reports canonical paths (for example /private/var for /var).
        let canonical: String? = root.path.withCString { path in
            guard let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        self.rootPrefixes = Set([root.standardizedFileURL.path, canonical ?? root.path])
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                                             kFSEventStreamCreateFlagUseCFTypes)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let eventPaths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if eventPaths.prefix(count).contains(where: watcher.isRelevant) {
                watcher.onChange()
            }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context,
                                               [root.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               0.5, flags) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    /// Ignores changes the scan would skip anyway: the index itself and
    /// anything inside a hidden file or folder (such as ~/Library or .git).
    /// Without this, background writes under a home folder trigger endless rescans.
    private func isRelevant(_ path: String) -> Bool {
        if path.hasPrefix(indexPath) { return false }
        guard let prefix = rootPrefixes.first(where: { path.hasPrefix($0) }) else { return true }
        let components = path.dropFirst(prefix.count).split(separator: "/")
        var current = URL(fileURLWithPath: String(prefix.dropLast()), isDirectory: true)
        for (index, component) in components.enumerated() {
            if component.hasPrefix(".") { return false }
            current.appendPathComponent(String(component))
            // The final component may already be deleted; only folders above it
            // need their hidden flag checked.
            if index < components.count - 1,
               (try? current.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true {
                return false
            }
        }
        return true
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
