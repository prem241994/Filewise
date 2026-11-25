import Combine
import FilewiseCore
import Foundation

enum ScanTestFailure: Error {
    case assertion(String)
}

@main
@MainActor
struct ScanSearchHarness {
    static func main() {
        do {
            try run()
            print("PASS: scan cancellation, date/type/size searches, FTS fallback, and missing/restricted folders")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ScanTestFailure.assertion(message) }
    }

    private static func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(45)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private static func run() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("filewise-scan-test-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("library", isDirectory: true)
        let otherRoot = base.appendingPathComponent("other", isDirectory: true)
        let restricted = base.appendingPathComponent("restricted", isDirectory: true)
        let missing = base.appendingPathComponent("missing", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restricted, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path)
            try? FileManager.default.removeItem(at: base)
        }

        let count = 3_006
        let app = root.appendingPathComponent("ExampleTool.app", isDirectory: true)
        let appContents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: appContents, withIntermediateDirectories: true)
        try Data("internal".utf8).write(to: appContents.appendingPathComponent("internal.txt"))
        let external = otherRoot.appendingPathComponent("external.txt")
        try Data("outside bundle".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: appContents.appendingPathComponent("link"), withDestinationURL: external)
        for index in 0..<3_000 {
            let name = index == 100 ? "specialtoken-report.txt" : String(format: "fixture-%04d.bin", index)
            let url = root.appendingPathComponent(name)
            let content = Data(repeating: UInt8(index % 251), count: index % 1024 + 1)
            try content.write(to: url)
        }

        // Mark one file as downloaded from Canva, as Safari does.
        let sourcePlist = try PropertyListSerialization.data(fromPropertyList: ["https://www.canva.com/design/abc"],
                                                             format: .binary, options: 0)
        let sourceResult = sourcePlist.withUnsafeBytes {
            setxattr(root.appendingPathComponent("specialtoken-report.txt").path,
                     "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, sourcePlist.count, 0, 0)
        }
        try require(sourceResult == 0, "could not set the download source fixture")

        let calendar = Calendar.current
        let previousWeek = try requireDate(calendar.dateInterval(of: .weekOfYear,
            for: calendar.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date())?.start)
        let currentWeek = try requireDate(calendar.dateInterval(of: .weekOfYear, for: Date())?.start)
        let previousPDF = root.appendingPathComponent("weekly-report.pdf")
        let currentPDF = root.appendingPathComponent("current-report.pdf")
        let largeVideo = root.appendingPathComponent("holiday.mov")
        let smallVideo = root.appendingPathComponent("short-clip.mp4")
        for file in [previousPDF, currentPDF, largeVideo, smallVideo] {
            try Data("fixture".utf8).write(to: file)
        }
        try FileManager.default.setAttributes([.modificationDate: previousWeek.addingTimeInterval(86_400)],
            ofItemAtPath: previousPDF.path)
        try FileManager.default.setAttributes([.modificationDate: currentWeek.addingTimeInterval(3_600)],
            ofItemAtPath: currentPDF.path)
        // Older than last week, with its own contents so it isn't a duplicate.
        let olderPDF = root.appendingPathComponent("older-summary.pdf")
        try Data("older".utf8).write(to: olderPDF)
        try FileManager.default.setAttributes([.modificationDate: previousWeek.addingTimeInterval(-14 * 86_400)],
            ofItemAtPath: olderPDF.path)
        let handle = try FileHandle(forWritingTo: largeVideo)
        try handle.truncate(atOffset: 101_000_000)
        try handle.close()

        let library = Library()
        var cancelled = false
        let subscription = library.$scannedCount.sink { scanned in
            if scanned >= 250 && !cancelled {
                cancelled = true
                library.cancelScan()
            }
        }
        library.scan(root)
        try require(waitUntil { cancelled && !library.scanning }, "scan cancellation timed out")
        subscription.cancel()
        try require(library.status == "Scan cancelled", "scan did not report cancellation")
        try require(library.files.isEmpty, "cancelled scan published partial results")
        try require((FileIndex.load(root: root) ?? []).isEmpty, "cancelled scan changed the saved index")

        library.scan(root)
        try require(waitUntil { !library.scanning && library.files.count == count },
                    "full large-folder scan timed out or missed files")
        try require(FileIndex.load(root: root)?.count == count, "large-folder index count was wrong")
        try require(library.files.filter { $0.libraryCategory == "Apps" }.map(\.name) == [app.lastPathComponent], "app bundle was not indexed as one app")
        try require(library.files.first { $0.name == app.lastPathComponent }?.size == 8, "app bundle size did not include its contents")
        try require(!library.files.contains { $0.name == "internal.txt" }, "app contents were indexed separately")
        try require(FileIndex.load(root: root)?.contains { $0.name == app.lastPathComponent && $0.libraryCategory == "Apps" } == true, "app did not persist in index")
        try Data("updated contents".utf8).write(to: appContents.appendingPathComponent("internal.txt"))
        library.scan(root)
        try require(waitUntil { !library.scanning }, "bundle refresh timed out")
        try require(library.files.first { $0.name == app.lastPathComponent }?.size == 16,
                    "bundle refresh did not update size or followed a symbolic link")
        library.category = "Apps"
        try require(waitUntil { library.visible.contains { $0.name == app.lastPathComponent } }, "Apps category did not show bundle")
        library.category = "Home"
        library.query = "ExampleTool"
        try require(waitUntil { library.visible.count == 1 && library.visible.first?.name == app.lastPathComponent }, "app name search failed")
        let lastScan = library.lastSuccessfulScan
        try require(lastScan != nil, "successful scan time missing")
        let storedDates = UserDefaults.standard.dictionary(forKey: "filewise.successfulScanDates")
        try require((storedDates?[root.standardizedFileURL.path] as? Date) == lastScan, "successful scan time was not persisted")

        library.query = "specialtoken"
        try require(waitUntil { library.visible.count == 1 && library.visible.first?.name == "specialtoken-report.txt" }, "FTS search did not find the known file")
        try require(library.visible.first?.name == "specialtoken-report.txt", "FTS returned the wrong file")
        try require(FileIndex.searchPaths(terms: ["specialtoken"], root: root)?.count == 1,
                    "root-scoped FTS search was unavailable")

        // "Last week" runs from the start of the previous week up to now.
        library.query = "pdfs from last week"
        try require(waitUntil { library.visible.map(\.name) == ["current-report.pdf", "weekly-report.pdf"] },
                    "last-week PDF search did not use file dates and types")
        try require(library.emptySearchHint == nil, "a search with results had an empty-search hint")
        // The videos were written just now, so none is from yesterday; the
        // hint should still find them on other dates.
        library.query = "videos from yesterday"
        try require(waitUntil { library.visible.isEmpty && library.emptySearchHint?.queryWithoutDate == "videos" },
                    "empty dated search had no hint")
        try require(library.emptySearchHint?.date.phrase == "from yesterday" && library.emptySearchHint?.newestMatch != nil,
                    "empty-search hint did not find the newest video")
        library.query = "large videos"
        try require(waitUntil { library.visible.map(\.name) == ["holiday.mov"] },
                    "large videos search treated the file type as a name keyword")
        library.query = "large files"
        try require(waitUntil { library.visible.map(\.name) == ["holiday.mov"] },
                    "large files search did not use the size threshold")

        // Identical "fixture" contents make the PDFs and the small video duplicates.
        library.query = "duplicates"
        try require(waitUntil { Set(library.visible.map(\.name)) == ["weekly-report.pdf", "current-report.pdf", "short-clip.mp4"] },
                    "duplicates keyword did not filter to duplicate files")
        library.query = "duplicate pdfs"
        try require(waitUntil { Set(library.visible.map(\.name)) == ["weekly-report.pdf", "current-report.pdf"] },
                    "duplicate keyword did not combine with a file type")
        library.query = "canva"
        try require(waitUntil { library.visible.map(\.name) == ["specialtoken-report.txt"] },
                    "download source search did not use the search index")
        library.query = "report"
        try require(waitUntil { library.visible.count == 3 }, "word-prefix search missed a hyphenated name")
        library.query = "eport"
        try require(waitUntil { library.visible.isEmpty }, "search matched the middle of a word")

        library.query = ""
        library.sortOrder = [KeyPathComparator(\FileItem.size, order: .reverse)]
        try require(waitUntil { library.visible.first?.name == "holiday.mov" }, "size sort did not put the largest file first")
        library.sortOrder = FileSearch.defaultSortOrder
        try require(waitUntil { library.visible.first?.modified == library.files.first?.modified },
                    "default sort did not restore newest-first order")
        let weekly = try requireItem(library.files.first { $0.name == "weekly-report.pdf" })
        try require(library.displayLocation(for: weekly) == root.lastPathComponent,
                    "a file at the folder root did not show the folder name as its location")
        try require(Set(library.otherCopies(of: weekly).map(\.name)) == ["current-report.pdf", "short-clip.mp4"],
                    "identical copies were not listed")
        try require(weekly.cleanupReasons == [.duplicate], "duplicate reason missing")
        try require(library.files.first { $0.name == "holiday.mov" }?.cleanupReasons == [.large], "large reason missing")

        library.category = "Downloaded From"
        try require(waitUntil { library.visible.count == library.summary(for: "Downloaded From").count
                                    && !library.visible.isEmpty },
                    "By Source count did not match its file list")

        library.category = "Documents"
        try require(waitUntil { !library.visible.isEmpty }, "Documents category was empty")
        library.toggleSelection(for: library.visible[0])
        library.category = "Apps"
        try require(library.selectedIDs.isEmpty, "selection carried over to another category")
        library.category = "Home"

        library.query = "specialtoken"

        // Simulate a different folder becoming the active FTS index while this
        // library still displays cached results. Filename matching must take over.
        let otherURL = otherRoot.appendingPathComponent("specialtoken-elsewhere.txt")
        try Data("other".utf8).write(to: otherURL)
        let other = FileItem(url: otherURL, size: 5, modified: Date(), changed: nil,
                             duplicate: false, hash: nil, downloadSource: nil)
        FileIndex.rebuildSearchIndex([other], root: otherRoot, token: ScanToken())
        try require(FileIndex.searchPaths(terms: ["specialtoken"], root: root) == nil,
                    "FTS leaked matches from another folder")
        library.updateVisible()
        try require(waitUntil { library.visible.count == 1 },
                    "cached results did not fall back to filename matching")
        library.query = "canva"
        try require(waitUntil { library.visible.map(\.name) == ["specialtoken-report.txt"] },
                    "fallback matching ignored the download source")
        library.query = "eport"
        try require(waitUntil { library.visible.isEmpty }, "fallback matching differed from the search index")

        library.query = ""
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: restricted.path)
        library.scan(restricted)
        try require(waitUntil { !library.scanning }, "restricted-folder scan did not finish")
        try require(library.status.contains("unavailable"),
                    "restricted folder was incorrectly indexed as empty")
        try require(!library.status.contains("saved results"),
                    "restricted folder claimed saved results when none were available")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path)

        library.scan(missing)
        try require(waitUntil { !library.scanning }, "missing-folder scan did not finish")
        try require(library.files.isEmpty, "missing folder showed the previous library")
        try require(library.status.contains("unavailable"),
                    "missing folder did not show an unavailable status")
        try require(!library.status.contains("saved results"),
                    "missing folder claimed saved results when none were available")

        library.scan(external)
        try require(waitUntil { !library.scanning }, "file-as-folder scan did not finish")
        try require(library.status.contains("unavailable"), "a regular file was incorrectly indexed as a folder")

        // Simulate an indexed external drive being disconnected and reconnected.
        let recoveryRoot = base.appendingPathComponent("recovery", isDirectory: true)
        let disconnectedRoot = base.appendingPathComponent("disconnected", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: recoveryRoot.appendingPathComponent("saved.txt"))
        library.scan(recoveryRoot)
        try require(waitUntil { !library.scanning && library.files.count == 1 }, "recovery fixture scan failed")
        try FileManager.default.moveItem(at: recoveryRoot, to: disconnectedRoot)
        library.scan(recoveryRoot)
        try require(waitUntil { !library.scanning }, "disconnected folder scan did not finish")
        try require(library.status.contains("showing saved results") && library.files.map(\.name) == ["saved.txt"],
                    "disconnected folder lost saved results")
        try require(FileIndex.load(root: recoveryRoot)?.count == 1, "disconnected folder replaced its index")
        try FileManager.default.moveItem(at: disconnectedRoot, to: recoveryRoot)
        try Data("new".utf8).write(to: recoveryRoot.appendingPathComponent("new.txt"))
        library.scan(recoveryRoot)
        try require(waitUntil { !library.scanning && library.files.count == 2 }, "reconnected folder did not refresh")
        try require(Set(library.files.map(\.name)) == Set(["saved.txt", "new.txt"]), "reconnected folder results were incorrect")
        try Data("after reconnect".utf8).write(to: recoveryRoot.appendingPathComponent("watched.txt"))
        try require(waitUntil { library.files.contains { $0.name == "watched.txt" } },
                    "file watcher did not detect changes after reconnecting the folder")

        // Old downloads count as forgotten only if they were not opened recently.
        let usageRoot = base.appendingPathComponent("usage", isDirectory: true)
        let downloads = usageRoot.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let opened = downloads.appendingPathComponent("opened-last-week.zip")
        let untouched = downloads.appendingPathComponent("untouched.zip")
        let twoMonthsAgo = Date().addingTimeInterval(-60 * 86_400)
        for file in [opened, untouched] {
            try Data(file.lastPathComponent.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: twoMonthsAgo], ofItemAtPath: file.path)
        }
        let lastWeek = Date().addingTimeInterval(-7 * 86_400)
        try setLastOpened(lastWeek, on: opened)
        library.scan(usageRoot)
        try require(waitUntil { !library.scanning && library.files.count == 2 }, "usage fixture scan failed")
        let openedItem = try requireItem(library.files.first { $0.name == "opened-last-week.zip" })
        try require(abs((openedItem.lastOpened?.timeIntervalSince1970 ?? 0) - lastWeek.timeIntervalSince1970) < 1,
                    "last-opened date was not read")
        try require(!openedItem.isForgottenDownload, "a recently opened download was called old")
        try require(library.files.first { $0.name == "untouched.zip" }?.isForgottenDownload == true,
                    "an unopened old download was not suggested")
        try require(FileIndex.load(root: usageRoot)?.first { $0.name == "opened-last-week.zip" }?.lastOpened != nil,
                    "last-opened date was not saved in the index")
        // Opening a file later must be noticed, not hidden by the saved value.
        try setLastOpened(Date(), on: untouched)
        library.scan(usageRoot)
        try require(waitUntil { !library.scanning && library.files.first { $0.name == "untouched.zip" }?.isForgottenDownload == false },
                    "a newly opened download stayed suggested after rescanning")

        // Settings: limits apply without rescanning; ignored folders need one.
        defer { CleanupSettings.current = CleanupSettings() }
        CleanupSettings.current = CleanupSettings(largeFileBytes: 10)
        library.applySettings(rescan: false)
        try require(library.summary(for: "Large Files").count == 2, "a lower large-file limit was not applied")
        try require(CleanupReason.large.explanation.contains("10 bytes"), "the large-file explanation ignored the setting")
        CleanupSettings.current = CleanupSettings(oldAfterDays: 3)
        library.applySettings(rescan: false)
        try require(library.files.first { $0.name == "opened-last-week.zip" }?.isForgottenDownload == true,
                    "a shorter age for old downloads was not applied")
        try require(library.summary(for: "Large Files").count == 0, "the default large-file limit was not restored")

        let privateFolder = usageRoot.appendingPathComponent("Private", isDirectory: true)
        try FileManager.default.createDirectory(at: privateFolder, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: privateFolder.appendingPathComponent("secret.txt"))
        library.scan(usageRoot)
        try require(waitUntil { !library.scanning && library.files.contains { $0.name == "secret.txt" } },
                    "the folder to ignore was not scanned first")
        CleanupSettings.current = CleanupSettings(ignoredFolders: [privateFolder.path])
        library.applySettings(rescan: true)
        try require(waitUntil { !library.scanning && !library.files.contains { $0.name == "secret.txt" } && library.files.count == 2 },
                    "an ignored folder was still scanned")
        try require(FileIndex.load(root: usageRoot)?.contains { $0.name == "secret.txt" } == false,
                    "an ignored folder stayed in the saved index")
        CleanupSettings.current = CleanupSettings()
        library.applySettings(rescan: true)
        try require(waitUntil { !library.scanning && library.files.contains { $0.name == "secret.txt" } },
                    "a folder was still skipped after it stopped being ignored")
    }

    /// Writes the attribute macOS records when a file is opened.
    private static func setLastOpened(_ date: Date, on url: URL) throws {
        let seconds = Int64(date.timeIntervalSince1970)
        let nanoseconds = Int64((date.timeIntervalSince1970 - Double(seconds)) * 1_000_000_000)
        var bytes: [UInt8] = []
        for value in [seconds, nanoseconds] {
            bytes += withUnsafeBytes(of: value.littleEndian, Array.init)
        }
        let result = setxattr(url.path, FileUsage.lastUsedAttribute, bytes, bytes.count, 0, 0)
        try require(result == 0, "could not set the last-opened fixture")
    }

    private static func requireItem(_ item: FileItem?) throws -> FileItem {
        guard let item else { throw ScanTestFailure.assertion("expected file missing") }
        return item
    }

    private static func requireDate(_ date: Date?) throws -> Date {
        guard let date else { throw ScanTestFailure.assertion("calendar week unavailable") }
        return date
    }
}
