import Foundation
import SQLite3
import Darwin

/// A local snapshot of file metadata for the currently selected folder.
public enum FileIndex {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    // Both are guarded by schemaLock.
    nonisolated(unsafe) private static var isSchemaInitialized = false
    private static let schemaLock = NSLock()
    nonisolated(unsafe) private static var _lastError: String?

    public static var lastError: String? {
        schemaLock.lock()
        defer { schemaLock.unlock() }
        return _lastError
    }

    public static var databaseDirectory: URL {
        if let testDirectory = ProcessInfo.processInfo.environment["FILEWISE_TEST_DATABASE_DIRECTORY"],
           !testDirectory.isEmpty {
            return URL(fileURLWithPath: testDirectory, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Filewise", isDirectory: true)
    }

    private static var databaseURL: URL { databaseDirectory.appendingPathComponent("index.sqlite") }

    private static func openDatabase() -> OpaquePointer? {
        schemaLock.lock()
        defer { schemaLock.unlock() }
        let url = databaseURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            _lastError = "Cannot access the index folder: \(error.localizedDescription)"
            return nil
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK else {
            _lastError = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open the index"
            sqlite3_close(database)
            return nil
        }
        sqlite3_busy_timeout(database, 5000)
        if !isSchemaInitialized {
            guard initializeSchema(in: database) else {
                sqlite3_close(database)
                return nil
            }
            isSchemaInitialized = true
        }
        _lastError = nil
        return database
    }

    // Migrations are atomic: a failed upgrade leaves the old database and Undo
    // records intact, and initialization is retried on the next open.
    private static func initializeSchema(in database: OpaquePointer?) -> Bool {
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            _lastError = String(cString: sqlite3_errmsg(database))
            return false
        }
        var committed = false
        defer {
            if !committed {
                _lastError = String(cString: sqlite3_errmsg(database))
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            }
        }
        let schema = """
            CREATE TABLE IF NOT EXISTS files (
                root TEXT NOT NULL, path TEXT NOT NULL, size INTEGER NOT NULL,
                modified REAL NOT NULL, changed REAL, duplicate INTEGER NOT NULL,
                hash BLOB, PRIMARY KEY (root, path)
            )
            """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else { return false }
        for (name, type) in [("changed", "REAL"), ("hash", "BLOB"), ("download_source", "TEXT")] {
            if !hasColumn(name, in: "files", database: database) {
                guard sqlite3_exec(database, "ALTER TABLE files ADD COLUMN \(name) \(type)", nil, nil, nil) == SQLITE_OK else { return false }
            }
        }
        // The search index is rebuildable. Older layouts without the download
        // source column are dropped and repopulated by the next scan.
        if hasTable("files_fts", in: database) && !hasColumn("source", in: "files_fts", database: database) {
            guard sqlite3_exec(database, "DROP TABLE files_fts", nil, nil, nil) == SQLITE_OK else { return false }
        }
        guard sqlite3_exec(database, """
            CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                name, kind, dirpath, source, filepath UNINDEXED
            )
            """, nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, """
            CREATE TABLE IF NOT EXISTS search_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
            """, nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, """
            CREATE TABLE IF NOT EXISTS trash_manifest (
                original_path TEXT PRIMARY KEY, trash_path TEXT NOT NULL,
                name TEXT NOT NULL, size INTEGER NOT NULL, trashed_at REAL NOT NULL,
                batch_id TEXT NOT NULL
            )
            """, nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
        committed = true
        return true
    }

    private static func hasTable(_ table: String, in database: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM sqlite_master WHERE name = ?", -1,
                                 &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func hasColumn(_ column: String, in table: String, database: OpaquePointer?) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1,
                                 &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1), String(cString: name) == column {
                return true
            }
        }
        return false
    }

    /// Clears only rebuildable search data. The Undo manifest stays in the same
    /// transaction and is never replaced. An unreadable database is left intact.
    public static func resetDerivedIndex() -> Bool {
        guard let database = openDatabase() else { return false }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }
        var committed = false
        defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }
        guard sqlite3_exec(database, "DELETE FROM files", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, "DELETE FROM files_fts", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, "DELETE FROM search_meta WHERE key = 'fts_root'", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
        committed = true
        return true
    }

    public static func load(root: URL) -> [FileItem]? {
        guard let database = openDatabase() else { return nil }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = "SELECT path, size, modified, changed, duplicate, hash, download_source FROM files WHERE root = ? ORDER BY modified DESC"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, root.path, -1, transient)

        var items: [FileItem] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let path = sqlite3_column_text(statement, 0) {
                let changed = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let hash: Data?
                if let bytes = sqlite3_column_blob(statement, 5), sqlite3_column_bytes(statement, 5) == 32 {
                    hash = Data(bytes: bytes, count: 32)
                } else {
                    hash = nil
                }
                let downloadSource: String?
                if sqlite3_column_type(statement, 6) != SQLITE_NULL, let text = sqlite3_column_text(statement, 6) {
                    downloadSource = String(cString: text)
                } else {
                    downloadSource = nil
                }
                items.append(FileItem(
                    url: URL(fileURLWithPath: String(cString: path)),
                    size: sqlite3_column_int64(statement, 1),
                    modified: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    changed: changed,
                    duplicate: sqlite3_column_int(statement, 4) != 0,
                    hash: hash,
                    downloadSource: downloadSource
                ))
            }
            result = sqlite3_step(statement)
        }
        return result == SQLITE_DONE ? items : nil
    }

    public static func save(_ items: [FileItem], root: URL,
                     previous: [FileItem]?, token: ScanToken) -> Bool {
        let oldByPath = Dictionary(uniqueKeysWithValues:
            (previous ?? []).map { ($0.url.path, $0) })
        let currentPaths = Set(items.map { $0.url.path })
        let removed = oldByPath.keys.filter { !currentPaths.contains($0) }
        let changed = items.filter { item in
            guard let old = oldByPath[item.url.path] else { return true }
            return old.size != item.size || old.modified != item.modified
                || old.changed != item.changed || old.duplicate != item.duplicate
                || old.hash != item.hash || old.downloadSource != item.downloadSource
        }
        if previous != nil && removed.isEmpty && changed.isEmpty {
            return !token.isCancelled
        }

        guard let database = openDatabase() else { return false }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return false }
        var committed = false
        defer {
            if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
        }

        var deleteStatement: OpaquePointer?
        let deleteSQL = previous == nil
            ? "DELETE FROM files WHERE root = ?"
            : "DELETE FROM files WHERE root = ? AND path = ?"
        guard sqlite3_prepare_v2(database, deleteSQL, -1,
                                 &deleteStatement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(deleteStatement) }
        let pathsToDelete = previous == nil ? [""] : removed
        for path in pathsToDelete {
            if token.isCancelled { return false }
            sqlite3_reset(deleteStatement)
            sqlite3_clear_bindings(deleteStatement)
            sqlite3_bind_text(deleteStatement, 1, root.path, -1, transient)
            if previous != nil { sqlite3_bind_text(deleteStatement, 2, path, -1, transient) }
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else { return false }
        }

        var insertStatement: OpaquePointer?
        let sql = """
            INSERT OR REPLACE INTO files (root, path, size, modified, changed, duplicate, hash, download_source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        guard sqlite3_prepare_v2(database, sql, -1, &insertStatement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(insertStatement) }

        for item in changed {
            if token.isCancelled { return false }
            sqlite3_reset(insertStatement)
            sqlite3_clear_bindings(insertStatement)
            sqlite3_bind_text(insertStatement, 1, root.path, -1, transient)
            sqlite3_bind_text(insertStatement, 2, item.url.path, -1, transient)
            sqlite3_bind_int64(insertStatement, 3, item.size)
            sqlite3_bind_double(insertStatement, 4, item.modified.timeIntervalSince1970)
            if let changed = item.changed {
                sqlite3_bind_double(insertStatement, 5, changed.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(insertStatement, 5)
            }
            sqlite3_bind_int(insertStatement, 6, item.duplicate ? 1 : 0)
            if let hash = item.hash {
                let bound = hash.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(insertStatement, 7, bytes.baseAddress,
                                      Int32(bytes.count), transient)
                }
                guard bound == SQLITE_OK else { return false }
            } else {
                sqlite3_bind_null(insertStatement, 7)
            }
            if let source = item.downloadSource {
                sqlite3_bind_text(insertStatement, 8, source, -1, transient)
            } else {
                sqlite3_bind_null(insertStatement, 8)
            }
            guard sqlite3_step(insertStatement) == SQLITE_DONE else { return false }
        }

        guard !token.isCancelled,
              sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
        committed = true
        return true
    }

    /// Quickly removes specific paths from both the files table and FTS search index.
    public static func removePaths(_ paths: Set<String>, root: URL) {
        guard !paths.isEmpty else { return }
        guard let database = openDatabase() else { return }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return }
        var committed = false
        defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }

        var deleteStmt: OpaquePointer?
        let sql = "DELETE FROM files WHERE root = ? AND path = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &deleteStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(deleteStmt) }

        for path in paths {
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            sqlite3_bind_text(deleteStmt, 1, root.path, -1, transient)
            sqlite3_bind_text(deleteStmt, 2, path, -1, transient)
            _ = sqlite3_step(deleteStmt)
        }

        // Fast bulk cleanup on FTS index: one single query instead of 20,000 unindexed full-table scans
        _ = sqlite3_exec(database, "DELETE FROM files_fts WHERE filepath NOT IN (SELECT path FROM files)", nil, nil, nil)

        if sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK {
            committed = true
        }
    }

    /// Rapidly adds or restores items into the files table and FTS search index without full rescan.
    public static func addItems(_ items: [FileItem], root: URL) {
        guard !items.isEmpty, let database = openDatabase() else { return }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return }
        var committed = false
        defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }

        var insertStmt: OpaquePointer?
        let sql = """
            INSERT OR REPLACE INTO files (root, path, size, modified, changed, duplicate, hash, download_source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        guard sqlite3_prepare_v2(database, sql, -1, &insertStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(insertStmt) }

        var ftsStmt: OpaquePointer?
        let ftsSql = "INSERT INTO files_fts (name, kind, dirpath, source, filepath) VALUES (?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, ftsSql, -1, &ftsStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(ftsStmt) }

        for item in items {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            sqlite3_bind_text(insertStmt, 1, root.path, -1, transient)
            sqlite3_bind_text(insertStmt, 2, item.url.path, -1, transient)
            sqlite3_bind_int64(insertStmt, 3, item.size)
            sqlite3_bind_double(insertStmt, 4, item.modified.timeIntervalSince1970)
            if let changed = item.changed {
                sqlite3_bind_double(insertStmt, 5, changed.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(insertStmt, 5)
            }
            sqlite3_bind_int(insertStmt, 6, item.duplicate ? 1 : 0)
            if let hash = item.hash {
                let bound = hash.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(insertStmt, 7, bytes.baseAddress, Int32(bytes.count), transient)
                }
                guard bound == SQLITE_OK else { return }
            } else {
                sqlite3_bind_null(insertStmt, 7)
            }
            if let src = item.downloadSource {
                sqlite3_bind_text(insertStmt, 8, src, -1, transient)
            } else {
                sqlite3_bind_null(insertStmt, 8)
            }
            guard sqlite3_step(insertStmt) == SQLITE_DONE else { return }

            sqlite3_reset(ftsStmt)
            sqlite3_clear_bindings(ftsStmt)
            sqlite3_bind_text(ftsStmt, 1, item.name, -1, transient)
            sqlite3_bind_text(ftsStmt, 2, item.kind, -1, transient)
            sqlite3_bind_text(ftsStmt, 3, item.url.deletingLastPathComponent().path, -1, transient)
            sqlite3_bind_text(ftsStmt, 4, item.downloadSource ?? "", -1, transient)
            sqlite3_bind_text(ftsStmt, 5, item.url.path, -1, transient)
            _ = sqlite3_step(ftsStmt)
        }

        if sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK {
            committed = true
        }
    }

    // MARK: - Trash Manifest & Undo

    @discardableResult
    public static func recordTrash(batchId: String, items: [TrashJournalEntry]) -> Bool {
        guard !items.isEmpty, let database = openDatabase() else { return false }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return false }
        var committed = false
        defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }

        var stmt: OpaquePointer?
        let sql = """
            INSERT OR REPLACE INTO trash_manifest (original_path, trash_path, name, size, trashed_at, batch_id)
            VALUES (?, ?, ?, ?, ?, ?)
            """
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let now = Date().timeIntervalSince1970
        for item in items {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, item.original, -1, transient)
            sqlite3_bind_text(stmt, 2, item.trash, -1, transient)
            sqlite3_bind_text(stmt, 3, item.name, -1, transient)
            sqlite3_bind_int64(stmt, 4, item.size)
            sqlite3_bind_double(stmt, 5, now)
            sqlite3_bind_text(stmt, 6, batchId, -1, transient)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
        }

        guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
        committed = true
        return true
    }

    public static func hasUnresolvedTrashMove(root: URL) -> Bool {
        guard let database = openDatabase() else { return false }
        defer { sqlite3_close(database) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT original_path FROM trash_manifest WHERE trash_path = ''", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let path = sqlite3_column_text(stmt, 0) else { continue }
            let original = String(cString: path)
            if original.hasPrefix(prefix) && !FileManager.default.fileExists(atPath: original) { return true }
        }
        return false
    }

    /// Reads recoverable manifest rows without modifying or migrating the source.
    /// A partial export is explicitly reported if SQLite encounters damage mid-read.
    public static func exportTrashRecords(to destination: URL) throws -> (count: Int, partial: Bool) {
        let directoryPath = databaseDirectory.standardizedFileURL.path
        let outputPath = destination.standardizedFileURL.path
        guard !outputPath.hasPrefix(directoryPath + "/"), outputPath != directoryPath else {
            throw NSError(domain: "FilewiseRecovery", code: 5, userInfo: [NSLocalizedDescriptionKey: "Choose a location outside the index folder to protect the original database."])
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(db)
            throw NSError(domain: "FilewiseRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT original_path, trash_path, name, size, trashed_at, batch_id FROM trash_manifest", -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "FilewiseRecovery", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: Any]] = []
        var result = sqlite3_step(stmt)
        while result == SQLITE_ROW {
            guard let original = sqlite3_column_text(stmt, 0), let trash = sqlite3_column_text(stmt, 1),
                  let name = sqlite3_column_text(stmt, 2), let batch = sqlite3_column_text(stmt, 5) else {
                throw NSError(domain: "FilewiseRecovery", code: 3, userInfo: [NSLocalizedDescriptionKey: "An Undo record is incomplete."])
            }
            rows.append(["original_path": String(cString: original), "trash_path": String(cString: trash),
                         "name": String(cString: name), "size": sqlite3_column_int64(stmt, 3),
                         "trashed_at": sqlite3_column_double(stmt, 4), "batch_id": String(cString: batch)])
            result = sqlite3_step(stmt)
        }
        guard result == SQLITE_DONE || !rows.isEmpty else {
            throw NSError(domain: "FilewiseRecovery", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
        let partial = result != SQLITE_DONE
        let data = try JSONSerialization.data(withJSONObject: ["partial": partial, "records": rows], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination, options: .atomic)
        return (rows.count, partial)
    }

    public static func latestTrashBatch(root: URL) -> String? {
        guard let database = openDatabase() else { return nil }
        defer { sqlite3_close(database) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT original_path, batch_id FROM trash_manifest WHERE trash_path != '' ORDER BY trashed_at DESC", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let path = sqlite3_column_text(stmt, 0), let batch = sqlite3_column_text(stmt, 1) else { continue }
            if String(cString: path).hasPrefix(prefix) { return String(cString: batch) }
        }
        return nil
    }

    public static func fetchTrashBatch(batchId: String) -> [TrashedRecord] {
        guard let database = openDatabase() else { return [] }
        defer { sqlite3_close(database) }

        var stmt: OpaquePointer?
        let sql = "SELECT original_path, trash_path, name, size, trashed_at, batch_id FROM trash_manifest WHERE batch_id = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, batchId, -1, transient)

        var records: [TrashedRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let orig = sqlite3_column_text(stmt, 0),
               let tr = sqlite3_column_text(stmt, 1),
               let nm = sqlite3_column_text(stmt, 2) {
                let sz = sqlite3_column_int64(stmt, 3)
                let dt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                let bid = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? batchId
                records.append(TrashedRecord(
                    originalPath: String(cString: orig),
                    trashPath: String(cString: tr),
                    name: String(cString: nm),
                    size: sz,
                    trashedAt: dt,
                    batchId: bid
                ))
            }
        }
        return records
    }

    public static func removeTrashRecords(originalPaths: Set<String>) {
        guard !originalPaths.isEmpty, let database = openDatabase() else { return }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { return }
        var committed = false
        defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }

        var stmt: OpaquePointer?
        let sql = "DELETE FROM trash_manifest WHERE original_path = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for path in originalPaths {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, path, -1, transient)
            _ = sqlite3_step(stmt)
        }

        if sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK {
            committed = true
        }
    }

    // MARK: - Full-Text Search

    /// Rebuilds the FTS5 search index from the given items and records which
    /// folder it covers. Called after a successful save to keep search in sync.
    public static func rebuildSearchIndex(_ items: [FileItem], root: URL, token: ScanToken) {
        guard let database = openDatabase() else { return }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION",
                           nil, nil, nil) == SQLITE_OK else { return }
        var committed = false
        defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }

        guard sqlite3_exec(database, "DELETE FROM files_fts",
                           nil, nil, nil) == SQLITE_OK else { return }

        var stmt: OpaquePointer?
        let sql = "INSERT INTO files_fts (name, kind, dirpath, source, filepath) VALUES (?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for item in items {
            guard !token.isCancelled else { return }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, item.name, -1, transient)
            sqlite3_bind_text(stmt, 2, item.kind, -1, transient)
            sqlite3_bind_text(stmt, 3, item.url.deletingLastPathComponent().path, -1, transient)
            sqlite3_bind_text(stmt, 4, item.downloadSource ?? "", -1, transient)
            sqlite3_bind_text(stmt, 5, item.url.path, -1, transient)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return }
        }

        var metaStmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO search_meta (key, value) VALUES ('fts_root', ?)",
                                 -1, &metaStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(metaStmt) }
        sqlite3_bind_text(metaStmt, 1, root.standardizedFileURL.path, -1, transient)
        guard sqlite3_step(metaStmt) == SQLITE_DONE else { return }

        guard !token.isCancelled,
              sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { return }
        committed = true
    }

    /// Queries the FTS5 index for files matching the given search terms.
    /// Returns the matching file paths (possibly empty), or nil when the index
    /// does not cover `root` (callers should fall back to in-memory filtering).
    public static func searchPaths(terms: [String], root: URL?) -> Set<String>? {
        guard !terms.isEmpty, let root else { return nil }
        guard let database = openDatabase() else { return nil }
        defer { sqlite3_close(database) }

        var metaStmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM search_meta WHERE key = 'fts_root'",
                                 -1, &metaStmt, nil) == SQLITE_OK else { return nil }
        let coveredRoot = sqlite3_step(metaStmt) == SQLITE_ROW
            ? sqlite3_column_text(metaStmt, 0).map { String(cString: $0) } : nil
        sqlite3_finalize(metaStmt)
        guard coveredRoot == root.standardizedFileURL.path else { return nil }

        // Build FTS5 query: each term becomes a prefix match, combined with implicit AND
        let ftsQuery = terms.compactMap { term -> String? in
            let clean = String(term.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            })
            return clean.isEmpty ? nil : "\"\(clean)\"*"
        }.joined(separator: " ")
        guard !ftsQuery.isEmpty else { return nil }

        var stmt: OpaquePointer?
        let sql = "SELECT filepath FROM files_fts WHERE files_fts MATCH ?"
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, transient)

        var paths = Set<String>()
        let rootPrefixes = PathPrefixes.forFolder(root)
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let p = sqlite3_column_text(stmt, 0) {
                let path = String(cString: p)
                if rootPrefixes.contains(where: path.hasPrefix) { paths.insert(path) }
            }
        }
        return paths
    }
}
