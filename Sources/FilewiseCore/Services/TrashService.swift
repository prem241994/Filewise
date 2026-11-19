import Foundation

/// The file operations a Trash batch uses. Tests replace them to exercise
/// failures, and to run where the real macOS Trash is inaccessible.
public struct TrashOperations: Sendable {
    public var moveToTrash: @Sendable (URL) throws -> URL?
    public var saveRecord: @Sendable (String, [TrashJournalEntry]) -> Bool

    public init(moveToTrash: @escaping @Sendable (URL) throws -> URL?,
                saveRecord: @escaping @Sendable (String, [TrashJournalEntry]) -> Bool) {
        self.moveToTrash = moveToTrash
        self.saveRecord = saveRecord
    }

    public static let system = TrashOperations(
        moveToTrash: { url in
            var result: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
            return result as URL?
        },
        saveRecord: { FileIndex.recordTrash(batchId: $0, items: $1) })
}

public enum TrashProgress: Sendable {
    case moving(processed: Int, name: String, bytesMoved: Int64, failedCount: Int)
    case updatingIndex
}

public struct TrashOutcome: Sendable {
    /// Original paths that are no longer in place, including any whose Trash
    /// location could not be recorded.
    public var trashedPaths = Set<String>()
    public var bytesMoved: Int64 = 0
    public var failedCount = 0
    /// The batch stopped because an Undo record could not be saved.
    public var journalFailed = false
    /// A file was moved but its Trash location is unknown to Filewise.
    public var manualRecovery = false
    /// The newest restorable batch for the folder after this operation.
    public var recordedBatch: String?
}

public struct RestoreOutcome: Sendable {
    public var restoredItems: [FileItem] = []
    public var restoredBytes: Int64 = 0
    public var failedCount = 0
}

/// Journaled Trash moves and Undo. Synchronous and blocking: call from
/// background work, never from the main actor.
public enum TrashService {
    /// Moves files to Trash one at a time. Each move is journaled before the
    /// file leaves its location and again once its Trash location is known;
    /// the batch stops at the first journal failure, rolling back the move in
    /// progress when it can.
    public static func moveToTrash(_ items: [FileItem], batchId: String, root: URL, token: ScanToken,
                                   operations: TrashOperations = .system,
                                   progress: (TrashProgress) -> Void) -> TrashOutcome {
        var outcome = TrashOutcome()
        var lastUpdate = Date()
        for (index, item) in items.enumerated() {
            if token.isCancelled { break }
            let original = item.url.path
            // Persist intent before the file leaves its original location.
            guard operations.saveRecord(batchId, [(original: original, trash: "", name: item.name, size: item.size)]) else {
                outcome.journalFailed = true
                break
            }
            do {
                guard let trashURL = try operations.moveToTrash(item.url), !trashURL.path.isEmpty else {
                    // The pending record remains as evidence for manual recovery.
                    outcome.trashedPaths.insert(original)
                    outcome.bytesMoved += item.size
                    outcome.journalFailed = true
                    outcome.manualRecovery = true
                    break
                }
                guard operations.saveRecord(batchId, [(original: original, trash: trashURL.path, name: item.name, size: item.size)]) else {
                    outcome.journalFailed = true
                    // Restore immediately when the final location cannot be recorded.
                    do {
                        try FileManager.default.moveItem(at: trashURL, to: item.url)
                        FileIndex.removeTrashRecords(originalPaths: [original])
                    } catch {
                        outcome.trashedPaths.insert(original)
                        outcome.bytesMoved += item.size
                        outcome.manualRecovery = true
                    }
                    break
                }
                outcome.trashedPaths.insert(original)
                outcome.bytesMoved += item.size
            } catch {
                FileIndex.removeTrashRecords(originalPaths: [original])
                NSLog("Failed to trash file: \(error)")
                outcome.failedCount += 1
            }

            let now = Date()
            if now.timeIntervalSince(lastUpdate) > 0.04 || index == items.count - 1 {
                lastUpdate = now
                progress(.moving(processed: index + 1, name: item.name,
                                 bytesMoved: outcome.bytesMoved, failedCount: outcome.failedCount))
            }
        }

        if !outcome.trashedPaths.isEmpty {
            progress(.updatingIndex)
            FileIndex.removePaths(outcome.trashedPaths, root: root)
        }
        outcome.recordedBatch = FileIndex.latestTrashBatch(root: root)
        if !outcome.trashedPaths.isEmpty && outcome.recordedBatch != batchId { outcome.journalFailed = true }
        return outcome
    }

    /// Restores a recorded batch to its original locations, renaming a file
    /// when its original name is taken. Returns nil when the batch has no
    /// records.
    public static func restore(batchId: String, root: URL) -> RestoreOutcome? {
        let records = FileIndex.fetchTrashBatch(batchId: batchId)
        guard !records.isEmpty else { return nil }

        var outcome = RestoreOutcome()
        var restoredPaths = Set<String>()
        for record in records {
            // Never guess a Trash location by name: another file could have
            // the same name. Empty paths are interrupted journal entries.
            guard !record.trashPath.isEmpty else { outcome.failedCount += 1; continue }
            let trashURL = URL(fileURLWithPath: record.trashPath)
            guard FileManager.default.fileExists(atPath: trashURL.path) else {
                outcome.failedCount += 1
                continue
            }

            var destURL = URL(fileURLWithPath: record.originalPath)
            let parentDir = destURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destURL.path) {
                let ext = destURL.pathExtension
                let base = destURL.deletingPathExtension().lastPathComponent
                var counter = 1
                repeat {
                    let newName = ext.isEmpty ? "\(base) (Restored \(counter))" : "\(base) (Restored \(counter)).\(ext)"
                    destURL = parentDir.appendingPathComponent(newName)
                    counter += 1
                } while FileManager.default.fileExists(atPath: destURL.path)
            }

            do {
                try FileManager.default.moveItem(at: trashURL, to: destURL)
                outcome.restoredBytes += record.size
                restoredPaths.insert(record.originalPath)

                let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .attributeModificationDateKey]
                let values = try? destURL.resourceValues(forKeys: keys)
                outcome.restoredItems.append(FileItem(
                    url: destURL,
                    size: Int64(values?.fileSize ?? Int(record.size)),
                    modified: values?.contentModificationDate ?? Date(),
                    changed: values?.attributeModificationDate,
                    duplicate: false,
                    hash: nil,
                    downloadSource: FileOriginExtractor.origin(for: destURL)
                ))
            } catch {
                NSLog("Failed to restore \(record.name): \(error)")
                outcome.failedCount += 1
            }
        }

        if !outcome.restoredItems.isEmpty {
            FileIndex.addItems(outcome.restoredItems, root: root)
        }
        if !restoredPaths.isEmpty {
            FileIndex.removeTrashRecords(originalPaths: restoredPaths)
        }
        return outcome
    }
}
