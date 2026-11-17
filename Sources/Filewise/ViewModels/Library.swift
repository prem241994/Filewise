import AppKit
import CryptoKit
import SwiftUI

struct LibrarySummary {
    var count = 0
    var bytes: Int64 = 0

    mutating func add(_ item: FileItem) {
        count += 1
        bytes += item.size
    }
}

final class Library: ObservableObject {
    @Published var folder: URL?
    @Published var customFolder: URL?
    @Published var files: [FileItem] = []
    @Published var scanning = false
    @Published var scannedCount = 0
    @Published var status = "Choose a folder to start"
    @Published var indexUnavailable = false
    @Published var lastSuccessfulScan: Date?
    @Published var query = "" {
        didSet {
            if query != oldValue {
                updateVisible()
            }
        }
    }
    @Published var category = "Home" {
        didSet {
            if category != oldValue {
                // Selection is per view, so files hidden by navigation can
                // never be moved to Trash by mistake.
                selectedIDs.removeAll()
                updateVisible()
            }
        }
    }
    @Published private(set) var visible: [FileItem] = []
    @Published private(set) var summaries: [String: LibrarySummary] = [:]
    @Published private(set) var downloadSources: [String: LibrarySummary] = [:]
    @Published var selectedIDs = Set<String>()
    @Published var inspectedItem: FileItem?
    @Published var previewURL: URL?
    @Published var bannerMessage: String?
    @Published var recentSearches: [String] = []
    @Published var isTrashing = false
    @Published var trashIsCompleted = false
    @Published var trashCurrentCount = 0
    @Published var trashTotalCount = 0
    @Published var trashFailedCount = 0
    @Published var trashCurrentName = ""
    @Published var trashBytesMoved: Int64 = 0
    @Published var canUndoTrash = false
    @Published var lastTrashBatchId: String?
    private var trashCancelToken: ScanToken?
    // Injectable file operation also allows the safety workflow to be tested in
    // environments where the real macOS Trash is inaccessible.
    var moveToTrash: (URL) throws -> URL? = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
    var saveTrashRecord: (String, [(original: String, trash: String, name: String, size: Int64)]) -> Bool = {
        FileIndex.recordTrash(batchId: $0, items: $1)
    }
    private var scanID = UUID()
    private var activeScan: ScanToken?
    private var watcher: FileWatcher?
    private var rescanWorkItem: DispatchWorkItem?
    private var searchWorkItem: DispatchWorkItem?
    private var visibleGeneration = 0
    private var changesDuringScan = false
    private static let folderBookmarkKey = "filewise.selectedFolderBookmark"
    private static let customFolderBookmarkKey = "filewise.customFolderBookmark"
    private static let bookmarkHasSecurityScopeKey = "filewise.bookmarkHasSecurityScope"
    private static let recentSearchesKey = "filewise.recentSearches"
    private static let scanDatesKey = "filewise.successfulScanDates"

    func addRecentSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var recents = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        recents.insert(trimmed, at: 0)
        if recents.count > 10 {
            recents = Array(recents.prefix(10))
        }
        recentSearches = recents
        UserDefaults.standard.set(recents, forKey: Self.recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
    }

    private func loadRecentSearches() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) {
            recentSearches = saved
        }
    }

    let categories = ["Home", "Recents", "Images", "Videos", "Music", "Documents", "Archives", "Apps", "Large Files", "Screenshots", "Duplicates", "Clean Up", "Downloads"]

    func summary(for category: String) -> LibrarySummary { summaries[category] ?? LibrarySummary() }

    // MARK: - Selection & Cleanup Actions

    func toggleSelection(for item: FileItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAllVisible() {
        for item in visible {
            selectedIDs.insert(item.id)
        }
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    var selectedFiles: [FileItem] {
        files.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    func selectDuplicateCopies() {
        let duplicates = files.filter { $0.duplicate }
        let grouped = Dictionary(grouping: duplicates) { item -> String in
            if let h = item.hash {
                return h.map { String(format: "%02hhx", $0) }.joined()
            }
            return "\(item.size)_\(item.name)"
        }

        var toSelect = Set<String>()
        for (_, group) in grouped where group.count > 1 {
            let sorted = group.sorted { $0.modified < $1.modified }
            for copy in sorted.dropFirst() {
                toSelect.insert(copy.id)
            }
        }
        selectedIDs = toSelect
        if !toSelect.isEmpty {
            bannerMessage = "Selected \(toSelect.count) duplicate copies to review."
        }
    }

    func cancelTrashing() {
        trashCancelToken?.cancel()
    }

    func trashFiles(items: [FileItem]) {
        guard !items.isEmpty, let root = folder else { return }

        let token = ScanToken()
        let batchId = UUID().uuidString
        self.trashCancelToken = token
        self.isTrashing = true
        self.trashIsCompleted = false
        self.trashCurrentCount = 0
        self.trashTotalCount = items.count
        self.trashFailedCount = 0
        self.trashCurrentName = items.first?.name ?? ""
        self.trashBytesMoved = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var trashedPaths = Set<String>()
            var bytesMoved: Int64 = 0
            var failedCount = 0
            var journalFailed = false
            var manualRecovery = false
            var lastUpdate = Date()

            for (index, item) in items.enumerated() {
                if token.isCancelled { break }
                let original = item.url.path
                let pending = (original: original, trash: "", name: item.name, size: item.size)
                // Persist intent before the file leaves its original location.
                guard self.saveTrashRecord(batchId, [pending]) else {
                    journalFailed = true
                    break
                }
                do {
                    let trashURL = try self.moveToTrash(item.url)
                    guard let trashURL, !trashURL.path.isEmpty else {
                        // The pending record remains as evidence for manual recovery.
                        trashedPaths.insert(original)
                        bytesMoved += item.size
                        journalFailed = true
                        manualRecovery = true
                        break
                    }
                    let record = (original: original, trash: trashURL.path, name: item.name, size: item.size)
                    guard self.saveTrashRecord(batchId, [record]) else {
                        journalFailed = true
                        // Restore immediately when the final location cannot be recorded.
                        do {
                            try FileManager.default.moveItem(at: trashURL, to: item.url)
                            FileIndex.removeTrashRecords(originalPaths: [original])
                        } catch {
                            trashedPaths.insert(original)
                            bytesMoved += item.size
                            manualRecovery = true
                        }
                        break
                    }
                    trashedPaths.insert(original)
                    bytesMoved += item.size
                } catch {
                    FileIndex.removeTrashRecords(originalPaths: [original])
                    NSLog("Failed to trash file: \(error)")
                    failedCount += 1
                }

                let now = Date()
                if now.timeIntervalSince(lastUpdate) > 0.04 || index == items.count - 1 {
                    lastUpdate = now
                    let currentCount = index + 1
                    let currentName = item.name
                    let currentBytes = bytesMoved
                    let currentFailures = failedCount
                    DispatchQueue.main.async {
                        self.trashCurrentCount = currentCount
                        self.trashCurrentName = currentName
                        self.trashBytesMoved = currentBytes
                        self.trashFailedCount = currentFailures
                    }
                }
            }

            if !trashedPaths.isEmpty {
                DispatchQueue.main.async { self.trashCurrentName = "Updating library index…" }
                FileIndex.removePaths(trashedPaths, root: root)
            }
            let recordedBatch = FileIndex.latestTrashBatch(root: root)
            if !trashedPaths.isEmpty && recordedBatch != batchId { journalFailed = true }
            DispatchQueue.main.async {
                self.trashCancelToken = nil
                self.selectedIDs.subtract(trashedPaths)
                if let inspected = self.inspectedItem, trashedPaths.contains(inspected.url.path) {
                    self.inspectedItem = nil
                }
                if let preview = self.previewURL, trashedPaths.contains(preview.path) {
                    self.previewURL = nil
                }

                let remaining = self.files.filter { !trashedPaths.contains($0.url.path) }
                self.updateFiles(remaining)

                let formatted = ByteCountFormatter.string(fromByteCount: bytesMoved, countStyle: .file)
                self.trashBytesMoved = bytesMoved
                self.trashFailedCount = failedCount
                self.lastTrashBatchId = recordedBatch
                self.canUndoTrash = recordedBatch != nil
                if journalFailed {
                    self.isTrashing = false
                    self.trashIsCompleted = false
                    self.bannerMessage = manualRecovery
                        ? "Stopped: a file was moved but its Trash location could not be saved. Check macOS Trash to restore it manually."
                        : "Stopped because Undo records could not be saved. No further files were moved."
                } else if token.isCancelled {
                    self.isTrashing = false
                    self.trashIsCompleted = false
                    self.bannerMessage = trashedPaths.isEmpty
                        ? "Cancelled before any files were moved to Trash"
                        : "Cancelled: Moved \(trashedPaths.count) of \(items.count) files (\(formatted)) to Trash. Undo is available."
                } else {
                    self.trashIsCompleted = true
                    self.trashCurrentCount = trashedPaths.count
                    self.trashCurrentName = "Completed"
                    self.bannerMessage = failedCount == 0 && !trashedPaths.isEmpty
                        ? "Moved \(trashedPaths.count) files (\(formatted)) to Trash. Undo is available."
                        : "Moved \(trashedPaths.count) of \(items.count) files to Trash; \(failedCount) could not be moved."
                }
            }
        }
    }

    func undoLastTrash() {
        guard let batchId = lastTrashBatchId, let root = folder else { return }
        lastTrashBatchId = nil
        canUndoTrash = false
        bannerMessage = "Restoring files from Trash…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let records = FileIndex.fetchTrashBatch(batchId: batchId)
            guard !records.isEmpty else {
                DispatchQueue.main.async {
                    self.bannerMessage = "No files found to restore."
                }
                return
            }

            var restoredCount = 0
            var restoredBytes: Int64 = 0
            var restoredPaths = Set<String>()
            var restoredItems: [FileItem] = []
            var failedCount = 0

            for record in records {
                // Never guess a Trash location by name: another file could have
                // the same name. Empty paths are interrupted journal entries.
                guard !record.trashPath.isEmpty else { failedCount += 1; continue }
                let trashURL = URL(fileURLWithPath: record.trashPath)
                guard FileManager.default.fileExists(atPath: trashURL.path) else {
                    failedCount += 1
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
                    restoredCount += 1
                    restoredBytes += record.size
                    restoredPaths.insert(record.originalPath)

                    let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .attributeModificationDateKey]
                    let vals = try? destURL.resourceValues(forKeys: keys)
                    let size = Int64(vals?.fileSize ?? Int(record.size))
                    let modified = vals?.contentModificationDate ?? Date()
                    let changed = vals?.attributeModificationDate
                    let source = FileOriginExtractor.origin(for: destURL)
                    restoredItems.append(FileItem(
                        url: destURL,
                        size: size,
                        modified: modified,
                        changed: changed,
                        duplicate: false,
                        hash: nil,
                        downloadSource: source
                    ))
                } catch {
                    NSLog("Failed to restore \(record.name): \(error)")
                    failedCount += 1
                }
            }

            if !restoredItems.isEmpty {
                FileIndex.addItems(restoredItems, root: root)
            }

            if !restoredPaths.isEmpty {
                FileIndex.removeTrashRecords(originalPaths: restoredPaths)
            }

            DispatchQueue.main.async {
                let formatted = ByteCountFormatter.string(fromByteCount: restoredBytes, countStyle: .file)
                if failedCount > 0 {
                    self.lastTrashBatchId = batchId
                    self.canUndoTrash = true
                }
                if failedCount == 0 {
                    self.bannerMessage = "Restored \(restoredCount) files (\(formatted)) from Trash"
                } else {
                    self.bannerMessage = "Restored \(restoredCount) files (\(formatted)), \(failedCount) could not be located"
                }
                var updated = self.files
                updated.append(contentsOf: restoredItems)
                updated.sort { $0.modified > $1.modified }
                self.updateFiles(updated)
            }
        }
    }

    func trashSelectedFiles() {
        let items = selectedFiles
        trashFiles(items: items)
    }

    var topDownloadSources: [(key: String, value: LibrarySummary)] {
        downloadSources.sorted { $0.value.count > $1.value.count }
    }

    private func updateFiles(_ items: [FileItem]) {
        var totals: [String: LibrarySummary] = [:]
        var sourcesTotals: [String: LibrarySummary] = [:]
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        for item in items {
            totals["Home", default: LibrarySummary()].add(item)
            if let category = item.libraryCategory { totals[category, default: LibrarySummary()].add(item) }
            if item.modified >= recentCutoff { totals["Recents", default: LibrarySummary()].add(item) }
            if item.isScreenshot { totals["Screenshots", default: LibrarySummary()].add(item) }
            if item.isOldScreenshot { totals["Old Screenshots", default: LibrarySummary()].add(item) }
            if item.isDownload { totals["Downloads", default: LibrarySummary()].add(item) }
            if item.isForgottenDownload { totals["Forgotten Downloads", default: LibrarySummary()].add(item) }
            if item.isLarge { totals["Large Files", default: LibrarySummary()].add(item) }
            if item.duplicate { totals["Duplicates", default: LibrarySummary()].add(item) }
            if item.duplicate || item.isOldScreenshot || item.isForgottenDownload || item.isLarge {
                totals["Clean Up", default: LibrarySummary()].add(item)
            }
            if let src = item.downloadSource {
                sourcesTotals[src, default: LibrarySummary()].add(item)
            }
        }
        summaries = totals
        downloadSources = sourcesTotals
        if !selectedIDs.isEmpty {
            selectedIDs.formIntersection(items.map(\.id))
        }
        files = items
        updateVisible(filesOverride: items)
    }

    init() {
        loadRecentSearches()
        updateVisible()
        guard ProcessInfo.processInfo.environment["FILEWISE_TEST_DATABASE_DIRECTORY"] == nil else { return }
        if let customData = UserDefaults.standard.data(forKey: Self.customFolderBookmarkKey) {
            var stale = false
            customFolder = try? URL(resolvingBookmarkData: customData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        guard let data = UserDefaults.standard.data(forKey: Self.folderBookmarkKey) else { return }
        let scoped = UserDefaults.standard.bool(forKey: Self.bookmarkHasSecurityScopeKey)
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                  options: scoped ? [.withSecurityScope] : [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) else { return }
        if customFolder == nil { customFolder = url }
        if stale { saveFolder(url) }
        DispatchQueue.main.async { self.scan(url) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        if panel.runModal() == .OK, let url = panel.url {
            rememberCustomFolder(url)
            saveFolder(url)
            scan(url)
        }
    }

    func selectLocation(_ url: URL, rememberCustom: Bool = false) {
        if rememberCustom { rememberCustomFolder(url) }
        guard folder?.path != url.path else { return }
        saveFolder(url)
        scan(url)
    }

    private func rememberCustomFolder(_ url: URL) {
        customFolder = url
        if let bookmark = try? url.bookmarkData() {
            UserDefaults.standard.set(bookmark, forKey: Self.customFolderBookmarkKey)
        }
    }

    private func saveFolder(_ url: URL) {
        let scopedData = try? url.bookmarkData(options: [.withSecurityScope])
        let data = scopedData ?? (try? url.bookmarkData())
        guard let data else { return }
        UserDefaults.standard.set(data, forKey: Self.folderBookmarkKey)
        UserDefaults.standard.set(scopedData != nil, forKey: Self.bookmarkHasSecurityScopeKey)
    }

    func cancelScan() {
        activeScan?.cancel()
        activeScan = nil
        watcher = nil
        rescanWorkItem?.cancel()
        rescanWorkItem = nil
        changesDuringScan = false
        scanID = UUID()
        scanning = false
        status = "Scan cancelled"
    }

    func rebuildIndex() {
        guard !scanning, !isTrashing, let folder else { return }
        if FileIndex.resetDerivedIndex() {
            indexUnavailable = false
            updateFiles([])
            scan(folder)
        } else {
            status = "Index could not be rebuilt; the original database and Undo records were kept."
            indexUnavailable = true
        }
    }

    func exportUndoRecords() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Filewise Undo Recovery.json"
        panel.message = "Save any readable Undo records from the index. File paths will be included."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let result = try FileIndex.exportTrashRecords(to: destination)
            bannerMessage = "Exported \(result.count) Undo records\(result.partial ? " (partial; database read failed)" : ""). The original database was kept."
        } catch {
            bannerMessage = "Could not export Undo records: \(error.localizedDescription). The original database was kept."
        }
    }

    func revealIndex() {
        NSWorkspace.shared.open(FileIndex.databaseDirectory)
    }

    func scan(_ url: URL) {
        activeScan?.cancel()
        if folder != url {
            lastTrashBatchId = nil
            canUndoTrash = false
            selectedIDs.removeAll()
            inspectedItem = nil
            previewURL = nil
            watcher = nil
            rescanWorkItem?.cancel()
            rescanWorkItem = nil
            changesDuringScan = false
            updateFiles([])
        }
        if watcher == nil {
            watcher = FileWatcher(root: url) { [weak self] in
                self?.scheduleRescan(for: url)
            }
        }
        let token = ScanToken()
        activeScan = token
        let id = UUID()
        scanID = id
        folder = url
        lastSuccessfulScan = (UserDefaults.standard.dictionary(forKey: Self.scanDatesKey)?[url.standardizedFileURL.path] as? Date)
        scanning = true
        scannedCount = 0
        status = "Scanning \(url.lastPathComponent)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let recoveredBatch = FileIndex.latestTrashBatch(root: url)
            let hasUnresolvedMove = FileIndex.hasUnresolvedTrashMove(root: url)
            DispatchQueue.main.async {
                guard self.scanID == id, !self.isTrashing, self.lastTrashBatchId == nil else { return }
                self.lastTrashBatchId = recoveredBatch
                self.canUndoTrash = recoveredBatch != nil
                if hasUnresolvedMove {
                    self.bannerMessage = "A previous Trash operation was interrupted. Check macOS Trash for any file that was not restored."
                } else if recoveredBatch != nil && self.bannerMessage == nil {
                    self.bannerMessage = "The last Trash batch can be restored."
                }
            }
            let loaded = FileIndex.load(root: url)
            let cached = loaded ?? []
            if !cached.isEmpty {
                DispatchQueue.main.async {
                    guard self.scanID == id, !token.isCancelled, self.files.isEmpty else { return }
                    self.updateFiles(cached)
                }
            }
            guard !token.isCancelled else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                DispatchQueue.main.async {
                    guard self.scanID == id, !token.isCancelled else { return }
                    self.scanning = false
                    self.activeScan = nil
                    self.watcher = nil
                    self.rescanWorkItem?.cancel()
                    self.rescanWorkItem = nil
                    self.changesDuringScan = false
                    self.status = self.files.isEmpty ? "Folder unavailable" : "Folder unavailable; showing saved results"
                }
                return
            }
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                          .contentModificationDateKey, .attributeModificationDateKey]
            var scanFailed = false
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in
                    scanFailed = true
                    return true
                })
            guard let enumerator else {
                DispatchQueue.main.async {
                    guard self.scanID == id, !token.isCancelled else { return }
                    self.scanning = false
                    self.activeScan = nil
                    self.watcher = nil
                    self.rescanWorkItem?.cancel()
                    self.rescanWorkItem = nil
                    self.changesDuringScan = false
                    self.status = self.files.isEmpty ? "Folder unavailable" : "Folder unavailable; showing saved results"
                }
                return
            }
            let cachedByPath = Dictionary(uniqueKeysWithValues: cached.map { ($0.url.path, $0) })
            var found: [FileItem] = []
            while !token.isCancelled, let file = enumerator.nextObject() as? URL {
                guard let values = try? file.resourceValues(forKeys: Set(keys)) else {
                    scanFailed = true
                    continue
                }
                let isAppBundle = file.pathExtension.lowercased() == "app"
                    && values.isDirectory == true && values.isSymbolicLink != true
                guard values.isRegularFile == true || isAppBundle else { continue }
                if isAppBundle { enumerator.skipDescendants() }
                let size = isAppBundle ? Self.bundleSize(file, token: token) : Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate ?? .distantPast
                let changed = values.attributeModificationDate
                let previous = cachedByPath[file.path]
                let reusableHash = previous?.size == size && previous?.modified == modified
                    && changed != nil && previous?.changed == changed ? previous?.hash : nil
                // A missing origin is also a cached result. Attribute changes
                // invalidate it, including when only download metadata changes.
                let source: String?
                if let previous, previous.size == size, previous.modified == modified,
                   let changed, previous.changed == changed {
                    source = previous.downloadSource
                } else {
                    source = FileOriginExtractor.origin(for: file)
                }
                found.append(FileItem(url: file, size: size, modified: modified,
                                      changed: changed, duplicate: false, hash: reusableHash,
                                      downloadSource: source))
                if found.count.isMultiple(of: 250) {
                    let count = found.count
                    DispatchQueue.main.async {
                        guard self.scanID == id else { return }
                        self.scannedCount = count
                    }
                }
            }
            guard !token.isCancelled else { return }
            if scanFailed {
                DispatchQueue.main.async {
                    guard self.scanID == id, !token.isCancelled else { return }
                    self.scanning = false
                    self.activeScan = nil
                    self.status = self.files.isEmpty ? "Some files unavailable" : "Some files unavailable; showing saved results"
                }
                return
            }
            let groups = Dictionary(grouping: found.indices.filter { found[$0].size > 0 && found[$0].kind != "app" },
                                    by: { found[$0].size })
            for group in groups.values where group.count > 1 {
                guard !token.isCancelled else { return }
                var hashes: [Data: [Int]] = [:]
                for index in group {
                    guard !token.isCancelled else { return }
                    let hash = found[index].hash ?? Self.digest(found[index].url, token: token)
                    found[index].hash = hash
                    if let hash { hashes[hash, default: []].append(index) }
                }
                for matches in hashes.values where matches.count > 1 {
                    for index in matches { found[index].duplicate = true }
                }
            }
            let items = found.sorted { $0.modified > $1.modified }
            let saved = FileIndex.save(items, root: url,
                                       previous: loaded, token: token)
            let indexError = saved ? nil : FileIndex.lastError
            if saved { FileIndex.rebuildSearchIndex(items, root: url, token: token) }
            DispatchQueue.main.async {
                guard self.scanID == id, !token.isCancelled else { return }
                self.updateFiles(items)
                self.scannedCount = items.count
                self.scanning = false
                self.activeScan = nil
                self.indexUnavailable = !saved
                if saved {
                    let now = Date()
                    self.lastSuccessfulScan = now
                    var dates = UserDefaults.standard.dictionary(forKey: Self.scanDatesKey) ?? [:]
                    dates[url.standardizedFileURL.path] = now
                    UserDefaults.standard.set(dates, forKey: Self.scanDatesKey)
                }
                self.status = saved ? "\(items.count.formatted()) files indexed" : "\(items.count.formatted()) files scanned; local index unavailable\(indexError.map { ": " + $0 } ?? "")"
                if self.changesDuringScan {
                    self.changesDuringScan = false
                    self.scheduleRescan(for: url)
                }
            }
        }
    }

    private func scheduleRescan(for url: URL) {
        guard folder == url else { return }
        rescanWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.folder == url else { return }
            self.rescanWorkItem = nil
            if self.scanning {
                self.changesDuringScan = true
            } else {
                self.scan(url)
            }
        }
        rescanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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

    func updateVisible(filesOverride: [FileItem]? = nil) {
        searchWorkItem?.cancel()
        // Filtering runs concurrently; only the newest request may publish,
        // so a slow older pass cannot restore files that were since removed.
        visibleGeneration += 1
        let generation = visibleGeneration

        let currentQuery = query
        let currentCategory = category
        let currentFiles = filesOverride ?? files
        let currentFolder = folder

        let isImmediate = currentQuery.isEmpty
        let delay: Double = isImmediate ? 0.0 : 0.06 // 60ms debounce for typing

        let work = DispatchWorkItem { [weak self] in
            let filtered = Self.filterFiles(
                files: currentFiles,
                query: currentQuery,
                category: currentCategory,
                folder: currentFolder
            )
            DispatchQueue.main.async {
                guard let self = self, self.visibleGeneration == generation else { return }
                self.visible = filtered
            }
        }
        searchWorkItem = work
        if delay == 0.0 {
            DispatchQueue.global(qos: .userInteractive).async(execute: work)
        } else {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private static func filterFiles(
        files: [FileItem],
        query: String,
        category: String,
        folder: URL?
    ) -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let lastWeek = trimmed.localizedCaseInsensitiveContains("last week")
        let recent = words.contains("recent")
        let wantsPDF = words.contains("pdf") || words.contains("pdfs")
        let wantsVideos = words.contains("video") || words.contains("videos")
        let screenshotAliases: Set<String> = [
            "screenshot", "screenshots", "screesnhot", "screesnshots",
            "screnshot", "screnshots", "screen", "screens"
        ]
        let wantsScreenshots = words.contains { word in
            word.hasPrefix("screenshot") || screenshotAliases.contains(word)
        }
        let wantsDownloads = words.contains("downloads") || words.contains("download")
        let wantsLarge = words.contains("large")
        let duplicateAliases: Set<String> = ["duplicate", "duplicates", "dupe", "dupes"]
        let wantsDuplicates = words.contains { duplicateAliases.contains($0) }
        var ignored = Set(["find", "show", "me", "my", "from", "in", "the", "a", "last", "week", "recent", "files", "file", "pdf", "pdfs", "video", "videos", "downloads", "download", "large"])
        ignored.formUnion(duplicateAliases)
        ignored.formUnion(screenshotAliases)
        let terms = words.filter { !ignored.contains($0) }
        let foldedTerms = terms.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let ftsMatchedPaths = terms.isEmpty ? nil : FileIndex.searchPaths(terms: terms, root: folder)
        let calendar = Calendar.current
        let previousWeek = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date())
        let recentCutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        return files.filter { item in
            let categoryMatch: Bool
            switch category {
            case "Recents": categoryMatch = item.modified >= recentCutoff
            case "Images", "Videos", "Music", "Documents", "Archives", "Apps": categoryMatch = item.libraryCategory == category
            case "Duplicates": categoryMatch = item.duplicate
            case "Screenshots": categoryMatch = item.isScreenshot
            case "Old Screenshots": categoryMatch = item.isOldScreenshot
            case "Forgotten Downloads": categoryMatch = item.isForgottenDownload
            case "Downloads": categoryMatch = item.isDownload
            case "Downloaded From": categoryMatch = item.downloadSource != nil || item.isDownload
            case "Large Files": categoryMatch = item.isLarge
            case "Clean Up": categoryMatch = item.duplicate || item.isOldScreenshot || item.isForgottenDownload || item.isLarge
            default:
                if category.hasPrefix("Origin: ") {
                    let target = String(category.dropFirst("Origin: ".count))
                    categoryMatch = item.downloadSource == target
                } else {
                    categoryMatch = true
                }
            }
            return (trimmed.isEmpty ? categoryMatch : true)
                && (!wantsPDF || item.kind == "pdf")
                && (!wantsVideos || item.libraryCategory == "Videos")
                && (!wantsScreenshots || item.isScreenshot)
                && (!wantsDownloads || item.isDownload)
                && (!wantsLarge || item.isLarge)
                && (!wantsDuplicates || item.duplicate)
                && (!lastWeek || (previousWeek?.contains(item.modified) ?? false))
                && (!recent || item.modified >= recentCutoff)
                && (terms.isEmpty || (ftsMatchedPaths.map { $0.contains(item.url.path) }
                    ?? matchesWordPrefixes(item, terms: foldedTerms)))
        }
    }

    /// In-memory equivalent of the FTS5 query, used while the search index
    /// covers a different folder: every term must begin a word in the file's
    /// name, parent folder path, or download source.
    private static func matchesWordPrefixes(_ item: FileItem, terms: [String]) -> Bool {
        let text = [item.name, item.url.deletingLastPathComponent().path, item.downloadSource ?? ""]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }

    var duplicateBytes: Int64 { summary(for: "Duplicates").bytes }
    var screenshotCount: Int { summary(for: "Old Screenshots").count }
}
