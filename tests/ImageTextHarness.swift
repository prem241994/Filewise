import AppKit
import FilewiseCore
import Foundation

enum ImageTextTestFailure: Error {
    case assertion(String)
}

/// Checks that the words inside screenshots are read on the device, stored,
/// searched, reused when unchanged, re-read when changed, and dropped when the
/// screenshot is gone. Other images are not read.
@main
@MainActor
struct ImageTextHarness {
    static func main() {
        do {
            try run()
            print("PASS: screenshot text reading, search by words in screenshots, reuse, re-reading, and removal")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ImageTextTestFailure.assertion(message) }
    }

    private static func waitUntil(_ seconds: TimeInterval = 60, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    /// Draws `text` in black on white, like a simple screenshot, as a PNG.
    private static func writeImage(_ text: String, to url: URL) throws {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1400, pixelsHigh: 320,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ImageTextTestFailure.assertion("could not create a bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1400, height: 320).fill()
        (text as NSString).draw(at: NSPoint(x: 60, y: 120),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 72, weight: .medium),
                                                 .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw ImageTextTestFailure.assertion("could not encode a PNG")
        }
        try png.write(to: url)
    }

    private static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("filewise-image-text-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let screenshot = root.appendingPathComponent("Screenshot 2026-11-20 at 10.00.00.png")
        let otherScreenshot = root.appendingPathComponent("Screenshot 2026-11-21 at 09.15.00.png")
        let photo = root.appendingPathComponent("holiday.png")
        try writeImage("Invoice 4821 for coffee beans", to: screenshot)
        try writeImage("Meeting notes", to: otherScreenshot)
        try writeImage("Invoice 9999 on a photo", to: photo)

        // Reading on its own.
        let read = ImageTextReader.read(screenshot) ?? ""
        try require(read.localizedCaseInsensitiveContains("invoice") && read.contains("4821"),
                    "text recognition read \"\(read)\"")
        try require(ImageTextReader.read(root.appendingPathComponent("missing.png")) == nil,
                    "a missing image did not fail to read")

        // A scan reads the screenshots (not the photo), and search finds the words.
        let library = Library()
        library.scan(root)
        try require(waitUntil { !library.scanning && library.files.count == 3 }, "scan did not finish")
        try require(waitUntil { library.textReading == nil && FileIndex.imageTextState(root: root).count == 2 },
                    "screenshot text was not read and stored")
        // The index stores the paths the scanner saw (/private/var/… for /var/…).
        func indexedPath(_ url: URL) -> String {
            library.files.first { $0.name == url.lastPathComponent }?.url.path ?? url.path
        }
        let screenshotPath = indexedPath(screenshot)
        let otherScreenshotPath = indexedPath(otherScreenshot)
        try require(FileIndex.imageTextState(root: root)[screenshotPath] != nil, "screenshot text stored under another path")
        try require(FileIndex.imageTextState(root: root)[indexedPath(photo)] == nil, "a photo that isn't a screenshot was read")

        library.query = "invoice"
        try require(waitUntil { library.visible.map(\.name) == [screenshot.lastPathComponent] },
                    "searching a word in the screenshot found \(library.visible.map(\.name))")
        library.query = "coffee invoice"
        try require(waitUntil { library.visible.map(\.name) == [screenshot.lastPathComponent] },
                    "two words from the screenshot did not both match")
        library.query = "screenshots meeting"
        try require(waitUntil { library.visible.map(\.name) == [otherScreenshot.lastPathComponent] },
                    "a type word plus a word in the screenshot did not match")
        library.query = "invoice meeting"
        try require(waitUntil { library.visible.isEmpty }, "words from two different screenshots matched one")
        try require(FileIndex.imageText(path: screenshotPath)?.contains("4821") == true,
                    "the inspector's stored text was missing")

        // An unchanged rescan reuses the stored text.
        let before = FileIndex.imageTextState(root: root)
        var sawReading = false
        library.query = ""
        library.scan(root)
        try require(waitUntil {
            if library.textReading != nil { sawReading = true }
            return !library.scanning
        }, "rescan did not finish")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        try require(!sawReading && library.textReading == nil, "unchanged screenshots were read again")
        try require(FileIndex.imageTextState(root: root).count == before.count, "stored text changed on an unchanged rescan")

        // A changed screenshot is read again.
        try writeImage("Receipt 77 for train tickets", to: screenshot)
        library.scan(root)
        try require(waitUntil { !library.scanning && library.textReading == nil
                && FileIndex.imageText(path: screenshotPath)?.localizedCaseInsensitiveContains("receipt") == true },
                    "a changed screenshot was not read again")
        library.query = "receipt"
        try require(waitUntil { library.visible.map(\.name) == [screenshot.lastPathComponent] }, "new text was not searchable")
        library.query = "invoice"
        try require(waitUntil { library.visible.isEmpty }, "old text was still searchable")

        // A removed screenshot's text is dropped.
        try FileManager.default.removeItem(at: otherScreenshot)
        library.query = ""
        library.scan(root)
        try require(waitUntil { !library.scanning && library.files.count == 2
                && FileIndex.imageTextState(root: root)[otherScreenshotPath] == nil },
                    "text for a deleted screenshot was kept")
    }
}
