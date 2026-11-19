import CryptoKit
import Foundation

public enum FolderScanOutcome: Sendable {
    /// The token was cancelled; nothing should be published.
    case cancelled
    /// The folder is missing, not a folder, or cannot be listed.
    case unavailable
    /// Some entries could not be read, so the result would be incomplete.
    /// Saved results must be kept rather than replaced.
    case incomplete
    /// Every readable file, newest first, with duplicates marked.
    case complete([FileItem])
}

/// Enumerates a folder's metadata and finds identical files. Synchronous and
/// blocking: call it from background work, never from the main actor.
public enum FolderScanner {
    /// - Parameters:
    ///   - previous: The saved index for this folder. Hashes and download
    ///     sources are reused for files whose size and change dates match.
    ///   - ignoredPaths: Folders to skip with everything inside them.
    ///   - progress: Called with the running file count every 250 files.
    public static func scan(_ url: URL, previous: [FileItem], token: ScanToken,
                            ignoredPaths: Set<String> = [],
                            progress: (Int) -> Void) -> FolderScanOutcome {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return .unavailable
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                      .contentModificationDateKey, .attributeModificationDateKey]
        var scanFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                scanFailed = true
                return true
            }) else { return .unavailable }

        let previousByPath = Dictionary(previous.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [FileItem] = []
        while !token.isCancelled, let file = enumerator.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else {
                scanFailed = true
                continue
            }
            if values.isDirectory == true, ignoredPaths.contains(file.path) {
                enumerator.skipDescendants()
                continue
            }
            let isAppBundle = file.pathExtension.lowercased() == "app"
                && values.isDirectory == true && values.isSymbolicLink != true
            guard values.isRegularFile == true || isAppBundle else { continue }
            if isAppBundle { enumerator.skipDescendants() }
            let size = isAppBundle ? bundleSize(file, token: token) : Int64(values.fileSize ?? 0)
            let modified = values.contentModificationDate ?? .distantPast
            let changed = values.attributeModificationDate
            let old = previousByPath[file.path]
            // Attribute changes invalidate cached values, including when only
            // download metadata changes. A missing origin is also cached.
            let unchanged = old?.size == size && old?.modified == modified
                && changed != nil && old?.changed == changed
            found.append(FileItem(url: file, size: size, modified: modified, changed: changed,
                                  duplicate: false,
                                  hash: unchanged ? old?.hash : nil,
                                  downloadSource: unchanged ? old?.downloadSource : FileOriginExtractor.origin(for: file),
                                  // Opening a file rewrites this attribute, which
                                  // changes the attribute date, so reuse is safe.
                                  lastOpened: unchanged ? old?.lastOpened : FileUsage.lastOpened(for: file)))
            if found.count.isMultiple(of: 250) { progress(found.count) }
        }
        guard !token.isCancelled else { return .cancelled }
        if scanFailed { return .incomplete }
        guard markDuplicates(&found, token: token) else { return .cancelled }
        return .complete(found.sorted { $0.modified > $1.modified })
    }

    /// Hashes only files that share a size with another file. Returns false
    /// when cancelled.
    private static func markDuplicates(_ found: inout [FileItem], token: ScanToken) -> Bool {
        let candidates = found.indices.filter { found[$0].size > 0 && found[$0].kind != "app" }
        let groups = Dictionary(grouping: candidates, by: { found[$0].size })
        for group in groups.values where group.count > 1 {
            var hashes: [Data: [Int]] = [:]
            for index in group {
                guard !token.isCancelled else { return false }
                let hash = found[index].hash ?? digest(found[index].url, token: token)
                found[index].hash = hash
                if let hash { hashes[hash, default: []].append(index) }
            }
            for matches in hashes.values where matches.count > 1 {
                for index in matches { found[index].duplicate = true }
            }
        }
        return !token.isCancelled
    }

    // Return zero when a bundle cannot be fully read, so a partial size is
    // never presented as an accurate cleanup estimate.
    private static func bundleSize(_ url: URL, token: ScanToken) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var failed = false
        guard let entries = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in
            failed = true
            return true
        }) else { return 0 }
        var total: Int64 = 0
        while !token.isCancelled, let entry = entries.nextObject() as? URL {
            guard let values = try? entry.resourceValues(forKeys: keys) else { failed = true; continue }
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard let fileSize = values.fileSize else { failed = true; continue }
            let (sum, overflow) = total.addingReportingOverflow(Int64(fileSize))
            if overflow { return 0 }
            total = sum
        }
        return failed || token.isCancelled ? 0 : total
    }

    private static func digest(_ url: URL, token: ScanToken) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                guard !token.isCancelled else { return nil }
                hash.update(data: chunk)
            }
            return Data(hash.finalize())
        } catch { return nil }
    }
}
