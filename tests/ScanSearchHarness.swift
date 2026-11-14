import Combine
import Foundation

enum ScanTestFailure: Error {
    case assertion(String)
}

@main
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

        let count = 3_005
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

        library.query = "pdfs from last week"
        try require(waitUntil { library.visible.map(\.name) == ["weekly-report.pdf"] },
                    "last-week PDF search did not use file dates and types")
        library.query = "large videos"
        try require(waitUntil { library.visible.map(\.name) == ["holiday.mov"] },
                    "large videos search treated the file type as a name keyword")
        library.query = "large files"
        try require(waitUntil { library.visible.map(\.name) == ["holiday.mov"] },
                    "large files search did not use the size threshold")

        library.query = "specialtoken"

        // Simulate a different folder becoming the active FTS index while this
        // library still displays cached results. Filename matching must take over.
        let otherURL = otherRoot.appendingPathComponent("specialtoken-elsewhere.txt")
        try Data("other".utf8).write(to: otherURL)
        let other = FileItem(url: otherURL, size: 5, modified: Date(), changed: nil,
                             duplicate: false, hash: nil, downloadSource: nil)
        FileIndex.rebuildSearchIndex([other], token: ScanToken())
        try require(FileIndex.searchPaths(terms: ["specialtoken"], root: root) == nil,
                    "FTS leaked matches from another folder")
        library.updateVisible()
        try require(waitUntil { library.visible.count == 1 },
                    "cached results did not fall back to filename matching")

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
    }

    private static func requireDate(_ date: Date?) throws -> Date {
        guard let date else { throw ScanTestFailure.assertion("calendar week unavailable") }
        return date
    }
}
