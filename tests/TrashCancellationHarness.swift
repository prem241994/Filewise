import Combine
import Foundation

enum TestFailure: Error {
    case assertion(String)
}

@main
struct TrashCancellationHarness {
    static func main() {
        do {
            try run()
            print("PASS: partial Trash cancellation retains index state and Undo restores files")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure.assertion(message) }
    }

    private static func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("filewise-trash-test-\(UUID().uuidString)", isDirectory: true)
        let count = 500
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var items: [FileItem] = []
        var batchId: String?
        defer {
            // Only this uniquely named temporary fixture is removed. Restore any
            // remaining test files from Trash first, including on failed assertions.
            if let batch = batchId {
                let records = FileIndex.fetchTrashBatch(batchId: batch)
                for record in records {
                    let trashURL = URL(fileURLWithPath: record.trashPath)
                    let originalURL = URL(fileURLWithPath: record.originalPath)
                    if FileManager.default.fileExists(atPath: trashURL.path) {
                        try? FileManager.default.moveItem(at: trashURL, to: originalURL)
                    }
                }
                FileIndex.removeTrashRecords(originalPaths: Set(records.map(\.originalPath)))
            }
            FileIndex.removePaths(Set(items.map { $0.url.path }), root: root)
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0..<count {
            let url = root.appendingPathComponent(String(format: "fixture-%04d.txt", index))
            try Data([UInt8(index % 251)]).write(to: url)
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .attributeModificationDateKey])
            items.append(FileItem(url: url, size: 1,
                                  modified: values.contentModificationDate ?? Date(),
                                  changed: values.attributeModificationDate,
                                  duplicate: false, hash: nil, downloadSource: nil))
        }
        try require(FileIndex.save(items, root: root, previous: nil, token: ScanToken()),
                    "fixture index was not saved")

        let library = Library()
        library.folder = root
        library.files = items
        var cancelRequested = false
        let subscription = library.$trashCurrentCount.sink { processed in
            if processed >= 3 && processed < count && !cancelRequested {
                cancelRequested = true
                library.cancelTrashing()
            }
        }
        defer { subscription.cancel() }

        library.trashFiles(items: items)
        try require(waitUntil { !library.isTrashing }, "cancellation timed out")
        let moved = count - items.filter { FileManager.default.fileExists(atPath: $0.url.path) }.count
        batchId = library.lastTrashBatchId
        try require(cancelRequested, "cancellation did not run during the batch")
        try require(moved > 0 && moved < count, "expected a partial batch; moved \(moved)")
        try require(library.canUndoTrash, "Undo was unavailable after partial cancellation")
        try require(library.trashBytesMoved == moved, "moved byte count was incorrect")
        guard let recordedBatchId = batchId else {
            throw TestFailure.assertion("partial batch had no undo identifier")
        }
        try require(FileIndex.fetchTrashBatch(batchId: recordedBatchId).count == moved,
                    "Trash manifest did not include every moved file")
        try require(FileIndex.load(root: root)?.count == count - moved,
                    "file index was not updated after cancellation")

        library.undoLastTrash()
        try require(waitUntil {
            items.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }
                && FileIndex.fetchTrashBatch(batchId: recordedBatchId).isEmpty
        }, "Undo did not restore all test files")
        try require(FileIndex.load(root: root)?.count == count, "restored files were not indexed")
    }
}
