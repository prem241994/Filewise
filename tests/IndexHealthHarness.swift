import Foundation
import SQLite3

@main struct IndexHealthHarness {
    static func main() throws {
        let directory = FileIndex.databaseDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("index.sqlite").path
        let mode = CommandLine.arguments[1]
        if mode == "corrupt" {
            try Data("not a sqlite database".utf8).write(to: URL(fileURLWithPath: path))
            precondition(FileIndex.load(root: URL(fileURLWithPath: "/tmp")) == nil)
            precondition(FileIndex.lastError != nil)
            precondition(!FileIndex.resetDerivedIndex())
            let invalidExport = directory.deletingLastPathComponent().appendingPathComponent("corrupt-export-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: invalidExport) }
            do {
                _ = try FileIndex.exportTrashRecords(to: invalidExport)
                fatalError("corrupt database unexpectedly exported")
            } catch { }
            precondition(FileIndex.load(root: URL(fileURLWithPath: "/tmp")) == nil)
            let unchanged = try Data(contentsOf: URL(fileURLWithPath: path))
            precondition(unchanged == Data("not a sqlite database".utf8))
        } else {
            var db: OpaquePointer?
            precondition(sqlite3_open(path, &db) == SQLITE_OK)
            let old = """
            CREATE TABLE files (root TEXT NOT NULL, path TEXT NOT NULL, size INTEGER NOT NULL, modified REAL NOT NULL, duplicate INTEGER NOT NULL, PRIMARY KEY(root,path));
            CREATE TABLE trash_manifest (original_path TEXT PRIMARY KEY, trash_path TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL, trashed_at REAL NOT NULL, batch_id TEXT NOT NULL);
            CREATE VIRTUAL TABLE files_fts USING fts5(name, kind, dirpath, filepath UNINDEXED);
            INSERT INTO files_fts VALUES ('example', '', '/tmp', '/tmp/example');
            INSERT INTO trash_manifest VALUES ('/original','/trash','file',42,1,'batch');
            INSERT INTO files VALUES ('/tmp','/tmp/example',42,1,0);
            """
            precondition(sqlite3_exec(db, old, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(db)
            let files = FileIndex.load(root: URL(fileURLWithPath: "/tmp"))
            precondition(files?.count == 1)
            precondition(FileIndex.fetchTrashBatch(batchId: "batch").first?.originalPath == "/original")
            precondition(FileIndex.lastError == nil)
            // The older search index is replaced, and is not used until rescanned.
            precondition(FileIndex.searchPaths(terms: ["example"], root: URL(fileURLWithPath: "/tmp")) == nil)
            let tmpItem = FileItem(url: URL(fileURLWithPath: "/tmp/example"), size: 42, modified: Date(), changed: nil,
                                   duplicate: false, hash: nil, downloadSource: "GitHub")
            FileIndex.rebuildSearchIndex([tmpItem], root: URL(fileURLWithPath: "/tmp"), token: ScanToken())
            precondition(FileIndex.searchPaths(terms: ["github"], root: URL(fileURLWithPath: "/tmp")) == ["/tmp/example"])
            precondition(FileIndex.searchPaths(terms: ["missing"], root: URL(fileURLWithPath: "/tmp")) == [])
            let exportURL = directory.deletingLastPathComponent().appendingPathComponent("export-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: exportURL) }
            let exported = try FileIndex.exportTrashRecords(to: exportURL)
            precondition(exported.count == 1 && !exported.partial)
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as! [String: Any]
            precondition((json["records"] as? [[String: Any]])?.first?["original_path"] as? String == "/original")
            precondition(sqlite3_open(path, &db) == SQLITE_OK)
            precondition(sqlite3_exec(db, "CREATE TRIGGER fail_manifest BEFORE INSERT ON trash_manifest BEGIN SELECT RAISE(FAIL, 'write failure'); END", nil, nil, nil) == SQLITE_OK)
            sqlite3_close(db)
            precondition(!FileIndex.recordTrash(batchId: "failure", items: [(original: "/new", trash: "/trash/new", name: "new", size: 1)]))
            precondition(FileIndex.fetchTrashBatch(batchId: "batch").count == 1)
            precondition(FileIndex.resetDerivedIndex())
            precondition(FileIndex.load(root: URL(fileURLWithPath: "/tmp"))?.isEmpty == true)
            precondition(FileIndex.searchPaths(terms: ["github"], root: URL(fileURLWithPath: "/tmp")) == nil)
            precondition(FileIndex.fetchTrashBatch(batchId: "batch").first?.originalPath == "/original")
        }
        print("PASS: index \(mode)")
    }
}
