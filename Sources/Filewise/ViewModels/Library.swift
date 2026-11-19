import AppKit
import FilewiseCore
import SwiftUI

/// The window's state. Runs on the main actor; scanning, searching, the index,
/// and Trash moves run in FilewiseCore on background tasks, and only their
/// results are applied here.
@MainActor
final class Library: ObservableObject {
    @Published var folder: URL? {
        didSet { folderPrefixes = folder.map(PathPrefixes.forFolder) ?? [] }
    }
    /// The selected folder's path, plus its canonical form when they differ.
    private var folderPrefixes: [String] = []
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
    @Published var selectedIDs = Set<String>() {
        didSet {
            if let id = playRequestID, !selectedIDs.contains(id) { playRequestID = nil }
        }
    }
    /// A video the user asked to play; the inspector starts it automatically.
    @Published private(set) var playRequestID: String?
    @Published var sortOrder = FileSearch.defaultSortOrder {
        didSet {
            if sortOrder != oldValue {
                updateVisible()
            }
        }
    }
    /// Lookup for selection and inspector; rebuilt whenever `files` changes.
    private(set) var filesByID: [String: FileItem] = [:]
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
    /// Replaced by tests to exercise failures without the real macOS Trash.
    var trashOperations = TrashOperations.system
    private var trashCancelToken: ScanToken?
    private var scanID = UUID()
    private var activeScan: ScanToken?
    private var watcher: FileWatcher?
    private var rescanTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var visibleGeneration = 0
    private var changesDuringScan = false
    private static let folderBookmarkKey = "filewise.selectedFolderBookmark"
    private static let customFolderBookmarkKey = "filewise.customFolderBookmark"
    private static let bookmarkHasSecurityScopeKey = "filewise.bookmarkHasSecurityScope"
    private static let recentSearchesKey = "filewise.recentSearches"
    private static let scanDatesKey = "filewise.successfulScanDates"

    init() {
        #if FILEWISE_SNAPSHOT
        SnapshotHook.library = self
        #endif
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
        Task { self.scan(url) }
    }

    /// Runs blocking file and database work off the main actor.
    private nonisolated static func background<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    // MARK: - Recent searches

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

    // MARK: - Summaries and lookup

    func summary(for category: String) -> LibrarySummary { summaries[category] ?? LibrarySummary() }

    var topDownloadSources: [(key: String, value: LibrarySummary)] {
        downloadSources.sorted { $0.value.count > $1.value.count }
    }

    var selectedFiles: [FileItem] {
        selectedIDs.compactMap { filesByID[$0] }.sorted { $0.modified > $1.modified }
    }

    /// Other files with identical contents.
    func otherCopies(of item: FileItem) -> [FileItem] {
        guard item.duplicate, let hash = item.hash else { return [] }
        return files.filter { $0.hash == hash && $0.id != item.id }
    }

    /// The containing folder relative to the selected folder, such as
    /// "Desktop › Downloads", falling back to the full path.
    func displayLocation(for item: FileItem) -> String {
        let parent = item.url.deletingLastPathComponent().path
        guard let folder else { return parent }
        let name = folder.lastPathComponent
        if folderPrefixes.contains(parent + "/") { return name }
        guard let prefix = folderPrefixes.first(where: { parent.hasPrefix($0) }) else { return parent }
        let relative = parent.dropFirst(prefix.count).split(separator: "/").joined(separator: " › ")
        return name + " › " + relative
    }

    private func updateFiles(_ items: [FileItem]) {
        (summaries, downloadSources) = LibrarySummary.totals(for: items)
        filesByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !selectedIDs.isEmpty {
            selectedIDs.formIntersection(filesByID.keys)
        }
        files = items
        updateVisible()
    }

    // MARK: - Selection

    func toggleSelection(for item: FileItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectAllVisible() {
        selectedIDs.formUnion(visible.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    /// Selects a video and asks the inspector to start playing it.
    func play(_ item: FileItem) {
        selectedIDs = [item.id]
        playRequestID = item.id
    }

    /// Selects every copy except the one `rule` keeps in each group of
    /// identical files.
    func selectDuplicateCopies(keeping rule: KeepRule = .oldest) {
        let extras = DuplicateSelection.extraCopies(in: files, keeping: rule)
        selectedIDs = extras
        bannerMessage = extras.isEmpty
            ? "No extra copies to select."
            : "Selected \(extras.count) extra \(extras.count == 1 ? "copy" : "copies"), keeping the \(rule.summary) in each group. Review them before moving to Trash."
    }

    /// Folders holding duplicates, for "keep the copy in this folder".
    var foldersWithDuplicates: [String] { DuplicateSelection.foldersWithDuplicates(in: files) }

    // MARK: - Trash and Undo

    func cancelTrashing() {
        trashCancelToken?.cancel()
    }

    func trashFiles(items: [FileItem]) {
        guard !items.isEmpty, let root = folder else { return }

        let token = ScanToken()
        let batchId = UUID().uuidString
        let operations = trashOperations
        trashCancelToken = token
        isTrashing = true
        trashIsCompleted = false
        trashCurrentCount = 0
        trashTotalCount = items.count
        trashFailedCount = 0
        trashCurrentName = items.first?.name ?? ""
        trashBytesMoved = 0

        Task {
            let outcome = await Self.background {
                TrashService.moveToTrash(items, batchId: batchId, root: root, token: token,
                                         operations: operations) { progress in
                    Task { @MainActor in self.applyTrashProgress(progress, token: token) }
                }
            }
            finishTrash(outcome, total: items.count, token: token)
        }
    }

    private func applyTrashProgress(_ progress: TrashProgress, token: ScanToken) {
        // Progress can arrive after the batch has finished; ignore it then.
        guard trashCancelToken === token else { return }
        switch progress {
        case let .moving(processed, name, bytesMoved, failedCount):
            trashCurrentCount = processed
            trashCurrentName = name
            trashBytesMoved = bytesMoved
            trashFailedCount = failedCount
        case .updatingIndex:
            trashCurrentName = "Updating library index…"
        }
    }

    private func finishTrash(_ outcome: TrashOutcome, total: Int, token: ScanToken) {
        let trashedPaths = outcome.trashedPaths
        trashCancelToken = nil
        selectedIDs.subtract(trashedPaths)
        if let preview = previewURL, trashedPaths.contains(preview.path) {
            previewURL = nil
        }
        updateFiles(files.filter { !trashedPaths.contains($0.url.path) })

        let formatted = ByteCountFormatter.string(fromByteCount: outcome.bytesMoved, countStyle: .file)
        trashBytesMoved = outcome.bytesMoved
        trashFailedCount = outcome.failedCount
        lastTrashBatchId = outcome.recordedBatch
        canUndoTrash = outcome.recordedBatch != nil
        if outcome.journalFailed {
            isTrashing = false
            trashIsCompleted = false
            bannerMessage = outcome.manualRecovery
                ? "Stopped: a file was moved but its Trash location could not be saved. Check macOS Trash to restore it manually."
                : "Stopped because Undo records could not be saved. No further files were moved."
        } else if token.isCancelled {
            isTrashing = false
            trashIsCompleted = false
            bannerMessage = trashedPaths.isEmpty
                ? "Cancelled before any files were moved to Trash"
                : "Cancelled: Moved \(trashedPaths.count) of \(total) files (\(formatted)) to Trash. Undo is available."
        } else {
            trashIsCompleted = true
            trashCurrentCount = trashedPaths.count
            trashCurrentName = "Completed"
            bannerMessage = outcome.failedCount == 0 && !trashedPaths.isEmpty
                ? "Moved \(trashedPaths.count) files (\(formatted)) to Trash. Undo is available."
                : "Moved \(trashedPaths.count) of \(total) files to Trash; \(outcome.failedCount) could not be moved."
        }
    }

    func undoLastTrash() {
        guard let batchId = lastTrashBatchId, let root = folder else { return }
        lastTrashBatchId = nil
        canUndoTrash = false
        bannerMessage = "Restoring files from Trash…"

        Task {
            guard let outcome = await Self.background({ TrashService.restore(batchId: batchId, root: root) }) else {
                bannerMessage = "No files found to restore."
                return
            }
            let restored = outcome.restoredItems
            let formatted = ByteCountFormatter.string(fromByteCount: outcome.restoredBytes, countStyle: .file)
            if outcome.failedCount > 0 {
                lastTrashBatchId = batchId
                canUndoTrash = true
                bannerMessage = "Restored \(restored.count) files (\(formatted)), \(outcome.failedCount) could not be located"
            } else {
                bannerMessage = "Restored \(restored.count) files (\(formatted)) from Trash"
            }
            updateFiles((files + restored).sorted { $0.modified > $1.modified })
        }
    }

    // MARK: - Folder selection

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

    // MARK: - Settings

    /// Applies changed cleanup settings: limits only need the counts and
    /// views recalculated, while ignored folders need a rescan.
    func applySettings(rescan: Bool) {
        if rescan, let folder {
            // A new watcher picks up the ignored folders.
            stopWatching()
            scan(folder)
        } else {
            updateFiles(files)
        }
    }

    // MARK: - Index maintenance

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

    // MARK: - Scanning

    func cancelScan() {
        activeScan?.cancel()
        activeScan = nil
        stopWatching()
        scanID = UUID()
        scanning = false
        status = "Scan cancelled"
    }

    private func stopWatching() {
        watcher = nil
        rescanTask?.cancel()
        rescanTask = nil
        changesDuringScan = false
    }

    func scan(_ url: URL) {
        activeScan?.cancel()
        if folder != url {
            lastTrashBatchId = nil
            canUndoTrash = false
            selectedIDs.removeAll()
            previewURL = nil
            stopWatching()
            updateFiles([])
        }
        if watcher == nil {
            watcher = FileWatcher(root: url, ignoring: CleanupSettings.current.ignoredPaths) { [weak self] in
                self?.scheduleRescan(for: url)
            }
        }
        let token = ScanToken()
        activeScan = token
        let id = UUID()
        scanID = id
        folder = url
        lastSuccessfulScan = UserDefaults.standard.dictionary(forKey: Self.scanDatesKey)?[url.standardizedFileURL.path] as? Date
        scanning = true
        scannedCount = 0
        status = "Scanning \(url.lastPathComponent)…"
        Task { await runScan(url, id: id, token: token) }
    }

    /// Whether `scan(_:)` call `id` is still the current, uncancelled scan.
    private func isCurrent(_ id: UUID, _ token: ScanToken) -> Bool {
        scanID == id && !token.isCancelled
    }

    private func runScan(_ url: URL, id: UUID, token: ScanToken) async {
        let (recoveredBatch, hasUnresolvedMove) = await Self.background {
            (FileIndex.latestTrashBatch(root: url), FileIndex.hasUnresolvedTrashMove(root: url))
        }
        if scanID == id, !isTrashing, lastTrashBatchId == nil {
            lastTrashBatchId = recoveredBatch
            canUndoTrash = recoveredBatch != nil
            if hasUnresolvedMove {
                bannerMessage = "A previous Trash operation was interrupted. Check macOS Trash for any file that was not restored."
            } else if recoveredBatch != nil && bannerMessage == nil {
                bannerMessage = "The last Trash batch can be restored."
            }
        }

        // Show the saved index while the folder is rescanned.
        let loaded = await Self.background { FileIndex.load(root: url) }
        let cached = loaded ?? []
        if !cached.isEmpty, isCurrent(id, token), files.isEmpty {
            updateFiles(cached)
        }
        guard !token.isCancelled else { return }

        let ignored = CleanupSettings.current.ignoredPaths
        let outcome = await Self.background {
            FolderScanner.scan(url, previous: cached, token: token, ignoredPaths: ignored) { count in
                Task { @MainActor in
                    guard self.activeScan === token else { return }
                    self.scannedCount = count
                }
            }
        }
        guard isCurrent(id, token) else { return }
        switch outcome {
        case .cancelled:
            return
        case .unavailable:
            scanning = false
            activeScan = nil
            stopWatching()
            status = files.isEmpty ? "Folder unavailable" : "Folder unavailable; showing saved results"
        case .incomplete:
            // Never replace saved results with a partial listing.
            scanning = false
            activeScan = nil
            status = files.isEmpty ? "Some files unavailable" : "Some files unavailable; showing saved results"
        case .complete(let items):
            let (saved, indexError) = await Self.background {
                let saved = FileIndex.save(items, root: url, previous: loaded, token: token)
                let error = saved ? nil : FileIndex.lastError
                if saved { FileIndex.rebuildSearchIndex(items, root: url, token: token) }
                return (saved, error)
            }
            guard isCurrent(id, token) else { return }
            updateFiles(items)
            scannedCount = items.count
            scanning = false
            activeScan = nil
            indexUnavailable = !saved
            if saved {
                let now = Date()
                lastSuccessfulScan = now
                var dates = UserDefaults.standard.dictionary(forKey: Self.scanDatesKey) ?? [:]
                dates[url.standardizedFileURL.path] = now
                UserDefaults.standard.set(dates, forKey: Self.scanDatesKey)
                status = "\(items.count.formatted()) files indexed"
            } else {
                status = "\(items.count.formatted()) files scanned; local index unavailable\(indexError.map { ": " + $0 } ?? "")"
            }
            if changesDuringScan {
                changesDuringScan = false
                scheduleRescan(for: url)
            }
        }
    }

    /// Coalesces bursts of file events into one rescan.
    private func scheduleRescan(for url: URL) {
        guard folder == url else { return }
        rescanTask?.cancel()
        rescanTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, folder == url else { return }
            rescanTask = nil
            if scanning {
                changesDuringScan = true
            } else {
                scan(url)
            }
        }
    }

    // MARK: - Search

    func updateVisible() {
        searchTask?.cancel()
        // Only the newest request may publish, so a slow older pass cannot
        // restore files that were since removed.
        visibleGeneration += 1
        let generation = visibleGeneration
        let (files, query, category, folder, sortOrder) = (files, query, category, folder, sortOrder)
        searchTask = Task {
            if !query.isEmpty {
                // Debounce typing.
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
            }
            let filtered = await Self.background {
                FileSearch.filter(files, query: query, category: category, folder: folder, sortOrder: sortOrder)
            }
            guard visibleGeneration == generation else { return }
            visible = filtered
        }
    }
}
