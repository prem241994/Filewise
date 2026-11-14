import Foundation

@main struct TrashSafetyHarness {
    static func wait(_ test: () -> Bool) {
        let deadline = Date().addingTimeInterval(30)
        while !test() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(test(), "operation timed out")
    }
    static func main() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("filewise-safety-\(UUID().uuidString)")
        let root = base.appendingPathComponent("files")
        let trash = base.appendingPathComponent("trash")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        func item(_ name: String) throws -> FileItem {
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return FileItem(url: url, size: Int64(name.utf8.count), modified: Date(), changed: nil, duplicate: false, hash: nil, downloadSource: nil)
        }
        func makeLibrary() -> Library {
            let library = Library()
            library.folder = root
            library.moveToTrash = { url in
                let target = trash.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: target)
                return target
            }
            return library
        }
        let first = try item("first.txt")
        let second = try item("second.txt")
        let library = makeLibrary()
        library.files = [first, second]
        var calls = 0
        library.saveTrashRecord = { batch, records in
            calls += 1
            return calls == 3 ? false : FileIndex.recordTrash(batchId: batch, items: records)
        }
        library.trashFiles(items: [first, second])
        wait { !library.isTrashing }
        precondition(!FileManager.default.fileExists(atPath: first.url.path))
        precondition(FileManager.default.fileExists(atPath: second.url.path))
        guard let batch = library.lastTrashBatchId else { fatalError("missing recorded batch") }
        precondition(library.canUndoTrash && FileIndex.fetchTrashBatch(batchId: batch).count == 1)
        precondition(FileIndex.latestTrashBatch(root: root) == batch)
        precondition(library.bannerMessage?.contains("could not be saved") == true)

        let restarted = makeLibrary()
        restarted.scan(root)
        wait { !restarted.scanning && restarted.lastTrashBatchId != nil }
        precondition(restarted.lastTrashBatchId == batch && restarted.canUndoTrash)
        restarted.undoLastTrash()
        wait { FileManager.default.fileExists(atPath: first.url.path) && FileIndex.fetchTrashBatch(batchId: batch).isEmpty }

        let third = try item("third.txt")
        let failure = makeLibrary()
        failure.files = [third]
        var saveCalls = 0
        failure.saveTrashRecord = { batch, records in
            saveCalls += 1
            return saveCalls == 2 ? false : FileIndex.recordTrash(batchId: batch, items: records)
        }
        failure.trashFiles(items: [third])
        wait { !failure.isTrashing }
        precondition(FileManager.default.fileExists(atPath: third.url.path), "failed journal update did not restore file")
        precondition(!failure.canUndoTrash)
        precondition(!FileIndex.hasUnresolvedTrashMove(root: root))

        let fourth = try item("fourth.txt")
        let blocked = makeLibrary()
        blocked.files = [fourth]
        blocked.saveTrashRecord = { _, _ in false }
        blocked.trashFiles(items: [fourth])
        wait { !blocked.isTrashing }
        precondition(FileManager.default.fileExists(atPath: fourth.url.path), "file moved despite journal failure")
        let fifth = try item("fifth.txt")
        let sixth = try item("sixth.txt")
        let cancelled = makeLibrary()
        cancelled.files = [fifth, sixth]
        cancelled.moveToTrash = { url in
            let target = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            cancelled.cancelTrashing()
            return target
        }
        cancelled.trashFiles(items: [fifth, sixth])
        wait { !cancelled.isTrashing }
        precondition(!FileManager.default.fileExists(atPath: fifth.url.path))
        precondition(FileManager.default.fileExists(atPath: sixth.url.path))
        guard let cancelledBatch = cancelled.lastTrashBatchId else { fatalError("cancelled batch was lost") }
        precondition(FileIndex.fetchTrashBatch(batchId: cancelledBatch).count == 1)
        cancelled.undoLastTrash()
        wait { FileManager.default.fileExists(atPath: fifth.url.path) && FileIndex.fetchTrashBatch(batchId: cancelledBatch).isEmpty }
        let missing = root.appendingPathComponent("interrupted.txt")
        precondition(FileIndex.recordTrash(batchId: "interrupted", items: [(original: missing.path, trash: "", name: missing.lastPathComponent, size: 1)]))
        precondition(FileIndex.hasUnresolvedTrashMove(root: root))
        FileIndex.removeTrashRecords(originalPaths: [missing.path])
        print("PASS: partial cancellation, journal failures, restart Undo, and safe rollback")
    }
}
