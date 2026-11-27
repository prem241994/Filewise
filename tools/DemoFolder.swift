import AppKit
import Foundation

/// Builds a realistic, made-up "My Files" folder for marketing screenshots and
/// the demo video: photos with real pictures, screenshots with readable text,
/// multi-page PDFs, duplicates, old installers, large videos, and downloads
/// from (invented) websites, with dates spread over the past months relative
/// to today. Nothing in it comes from a real person or company.
/// Large media and installers are sparse files: they report realistic sizes
/// but take almost no disk space.
/// Run by scripts/make-demo-folder.sh; not part of the app.

let calendar = Calendar.current
let now = Date()

func daysAgo(_ days: Double, hour: Int = 10, minute: Int = 0) -> Date {
    let day = calendar.date(byAdding: .day, value: -Int(days), to: now)!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

/// "Screenshot 2026-11-26 at 16.42.10.png", the way macOS names them.
func screenshotName(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Screenshot \(f.string(from: date)).png"
}

struct Folder {
    let root: URL
    func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    func prepare(_ relative: String) -> URL {
        let url = self.url(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    /// Sets the file's dates; `lastOpened` writes the attribute macOS uses for "Date Last Opened".
    func date(_ relative: String, _ date: Date, lastOpened: Date? = nil) {
        let url = self.url(relative)
        try? FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
        if let lastOpened {
            var spec = timespec(tv_sec: Int(lastOpened.timeIntervalSince1970), tv_nsec: 0)
            _ = withUnsafeBytes(of: &spec) { bytes in
                setxattr(url.path, "com.apple.lastuseddate#PS", bytes.baseAddress, 16, 0, 0)
            }
        }
    }

    /// Records the web address a download came from, as browsers do.
    func source(_ relative: String, _ address: String) {
        let data = try! PropertyListSerialization.data(fromPropertyList: [address], format: .binary, options: 0)
        _ = data.withUnsafeBytes { bytes in
            setxattr(url(relative).path, "com.apple.metadata:kMDItemWhereFroms", bytes.baseAddress, data.count, 0, 0)
        }
    }

    /// A file of `megabytes` that takes no real space.
    func sparse(_ relative: String, megabytes: Double) {
        let url = prepare(relative)
        FileManager.default.createFile(atPath: url.path, contents: Data("demo".utf8))
        let handle = try! FileHandle(forWritingTo: url)
        try! handle.truncate(atOffset: UInt64(megabytes * 1_048_576))
        try! handle.close()
    }

    func text(_ relative: String, _ content: String) {
        try! content.write(to: prepare(relative), atomically: true, encoding: .utf8)
    }

    func copy(_ from: String, to: String) {
        let destination = prepare(to)
        try? FileManager.default.removeItem(at: destination)
        try! FileManager.default.copyItem(at: url(from), to: destination)
    }
}

// MARK: - Drawing helpers

func bitmap(_ width: Int, _ height: Int, draw: (CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    // Flip so y runs down, like a page, and tell AppKit so text draws upright.
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Draws text with its top-left at `point` in a flipped context.
func write(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular,
           color textColor: NSColor = color(0x1d1d1f), width: CGFloat = 2000) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                     .foregroundColor: textColor]
    NSAttributedString(string: string, attributes: attributes)
        .draw(with: CGRect(x: point.x, y: point.y, width: width, height: size * 40),
              options: [.usesLineFragmentOrigin, .usesFontLeading])
}

func fill(_ rect: CGRect, _ fillColor: NSColor, radius: CGFloat = 0) {
    fillColor.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func savePNG(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func saveJPEG(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: url)
}

// MARK: - Screenshots with readable text

/// A browser-like window on a soft background, with a card of text inside.
func screenshot(title: String, accent: UInt32, lines: [(String, CGFloat, NSFont.Weight)], to url: URL) {
    let rep = bitmap(1600, 1000) { bounds in
        fill(bounds, color(0xe9e7f3))
        let window = CGRect(x: 120, y: 80, width: 1360, height: 840)
        fill(window.offsetBy(dx: 0, dy: 10), color(0x000000, 0.08), radius: 18)
        fill(window, .white, radius: 16)
        fill(CGRect(x: window.minX, y: window.minY, width: window.width, height: 56), color(0xf3f2f7), radius: 16)
        fill(CGRect(x: window.minX, y: window.minY + 40, width: window.width, height: 16), color(0xf3f2f7))
        for (i, dot) in [0xff5f57, 0xfebc2e, 0x28c840].enumerated() {
            fill(CGRect(x: window.minX + 22 + CGFloat(i) * 22, y: window.minY + 21, width: 14, height: 14), color(UInt32(dot)), radius: 7)
        }
        fill(CGRect(x: window.minX + 420, y: window.minY + 14, width: 520, height: 28), .white, radius: 8)
        write(title, at: CGPoint(x: window.minX + 440, y: window.minY + 18), size: 15, color: color(0x6e6e73))
        fill(CGRect(x: window.minX, y: window.minY + 56, width: window.width, height: 8), color(accent))
        var y = window.minY + 110
        for (text, size, weight) in lines {
            write(text, at: CGPoint(x: window.minX + 90, y: y), size: size, weight: weight,
                  color: weight == .bold || weight == .heavy ? color(0x1d1d1f) : color(0x3a3a3c), width: 1180)
            y += size * 1.9
        }
    }
    savePNG(rep, url)
}

// MARK: - Photos

/// A simple landscape: sky gradient, sun, layered hills, and water.
func photo(seed: Int, to url: URL, width: Int = 3000, height: Int = 2000) {
    let palettes: [[UInt32]] = [
        [0xffb46b, 0xff7a59, 0x6b4c9a, 0x2d3a6b, 0x1f5f7a],
        [0x9fd7ff, 0x5aa9e6, 0x3f7f5f, 0x2f5d46, 0x2b6f9e],
        [0xffd29d, 0xf6a6b2, 0x8a6fb5, 0x4b3f72, 0x3d6f8f],
        [0xbfe6ff, 0x7cc4f0, 0x6e9b4a, 0x4a7a35, 0x3a8fb5],
    ]
    let p = palettes[seed % palettes.count]
    let rep = bitmap(width, height) { b in
        let ctx = NSGraphicsContext.current!.cgContext
        let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [color(p[0]).cgColor, color(p[1]).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: b.height * 0.65), options: [])
        let sunX = b.width * (0.25 + 0.5 * CGFloat((seed * 37) % 10) / 10)
        fill(CGRect(x: sunX - 140, y: b.height * 0.28, width: 280, height: 280), color(0xfff4d6, 0.9), radius: 140)
        for layer in 0..<3 {
            let path = NSBezierPath()
            let base = b.height * (0.5 + CGFloat(layer) * 0.08)
            path.move(to: CGPoint(x: 0, y: b.height))
            path.line(to: CGPoint(x: 0, y: base))
            var x: CGFloat = 0
            var step = 0
            while x < b.width {
                x += b.width / 6
                step += 1
                let peak = base - CGFloat(((seed + layer * 3 + step * 7) % 5) + 1) * b.height * 0.035
                path.curve(to: CGPoint(x: x, y: base - CGFloat(step % 2) * 40),
                           controlPoint1: CGPoint(x: x - b.width / 9, y: peak),
                           controlPoint2: CGPoint(x: x - b.width / 18, y: peak))
            }
            path.line(to: CGPoint(x: b.width, y: b.height))
            path.close()
            color(p[2 + min(layer, 1)], 1 - CGFloat(layer) * 0.15).setFill()
            path.fill()
        }
        fill(CGRect(x: 0, y: b.height * 0.8, width: b.width, height: b.height * 0.2), color(p[4], 0.92))
        for i in 0..<14 {
            fill(CGRect(x: CGFloat((i * 211 + seed * 97) % width), y: b.height * 0.83 + CGFloat(i % 5) * 50,
                        width: 160, height: 6), color(0xffffff, 0.35), radius: 3)
        }
    }
    saveJPEG(rep, url)
}

// MARK: - PDFs

/// A multi-page PDF with a title, text, and (optionally) a bar chart on page one.
func pdf(title: String, subtitle: String, paragraphs: [String], chart: Bool = false, pages: Int = 2, to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    for page in 0..<pages {
        ctx.beginPDFPage(nil)
        ctx.translateBy(x: 0, y: 792)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        fill(CGRect(x: 0, y: 0, width: 612, height: 10), color(0x5b4cf5))
        if page == 0 {
            write(title, at: CGPoint(x: 56, y: 60), size: 26, weight: .bold, width: 500)
            write(subtitle, at: CGPoint(x: 56, y: 100), size: 12, color: color(0x6e6e73), width: 500)
        }
        var y: CGFloat = page == 0 ? 150 : 60
        if chart && page == 0 {
            let values: [CGFloat] = [0.45, 0.62, 0.58, 0.81]
            for (i, v) in values.enumerated() {
                fill(CGRect(x: 80 + CGFloat(i) * 120, y: y + 160 * (1 - v), width: 70, height: 160 * v), color(0x5b4cf5, 0.55 + 0.1 * CGFloat(i)), radius: 4)
                write(["Jul", "Aug", "Sep", "Oct"][i], at: CGPoint(x: 98 + CGFloat(i) * 120, y: y + 168), size: 11, color: color(0x6e6e73))
            }
            y += 210
        }
        for paragraph in paragraphs {
            write(paragraph, at: CGPoint(x: 56, y: y), size: 11.5, color: color(0x3a3a3c), width: 500)
            y += 110
            if y > 700 { break }
        }
        write("Page \(page + 1) of \(pages)", at: CGPoint(x: 268, y: 752), size: 9, color: color(0x8e8e93))
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

let lorem = [
    "This document summarises the work completed this quarter, the results against our goals, and the priorities for the months ahead. Figures are rounded to the nearest whole number.",
    "Revenue grew steadily across all regions, led by strong demand in the second half of the quarter. Operating costs stayed within budget, and customer satisfaction scores improved.",
    "Next quarter we will focus on three areas: shipping the new onboarding flow, reducing support response times, and expanding into two new markets.",
    "Please review the attached figures before the planning meeting and send any questions to the team lead by Friday.",
]

// MARK: - Build the folder

@main
struct DemoFolderBuilder {
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: demo-folder <output folder>\n", stderr)
            exit(2)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try? FileManager.default.removeItem(at: root)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let f = Folder(root: root)

        // Screenshots with words in them (recent), so "invoice" finds one.
        let invoiceDate = daysAgo(1, hour: 16, minute: 42)
        let invoiceShot = "Desktop/" + screenshotName(invoiceDate)
        screenshot(title: "northwind-coffee.example/orders/4821", accent: 0x8b5a2b, lines: [
            ("Northwind Coffee Roasters", 40, .bold),
            ("INVOICE #4821", 24, .semibold),
            ("Billed to: Alex Morgan · Issued 26 Nov 2026 · Due 10 Dec 2026", 20, .regular),
            ("Ethiopia Yirgacheffe, 1 kg ............................ $24.00", 22, .regular),
            ("House Espresso Blend, 2 kg ............................ $38.00", 22, .regular),
            ("Shipping ............................................. $6.00", 22, .regular),
            ("Total due: $68.00", 30, .bold),
        ], to: f.prepare(invoiceShot))
        f.date(invoiceShot, invoiceDate)

        let boardingDate = daysAgo(3, hour: 7, minute: 5)
        let boardingShot = "Desktop/" + screenshotName(boardingDate)
        screenshot(title: "skyline-air.example/boarding-pass", accent: 0x1f6feb, lines: [
            ("Skyline Air · Boarding Pass", 40, .bold),
            ("Bengaluru (BLR)  →  Goa (GOI)", 30, .semibold),
            ("Flight SK 342 · 29 Nov 2026", 22, .regular),
            ("Gate 12 · Seat 14A · Boarding 07:35", 26, .semibold),
            ("Passenger: Alex Morgan · Booking ref QX7P2L", 20, .regular),
        ], to: f.prepare(boardingShot))
        f.date(boardingShot, boardingDate)

        let notesDate = daysAgo(6, hour: 11, minute: 20)
        let notesShot = "Desktop/" + screenshotName(notesDate)
        screenshot(title: "Notes", accent: 0xf5a623, lines: [
            ("Q4 launch checklist", 40, .bold),
            ("•  Final app icon and App Store screenshots", 24, .regular),
            ("•  Write the launch email for the waitlist", 24, .regular),
            ("•  Test the 7-day trial on a clean Mac", 24, .regular),
            ("•  Book the meeting room for Thursday 3 PM", 24, .regular),
        ], to: f.prepare(notesShot))
        f.date(notesShot, notesDate)

        let wifiDate = daysAgo(9, hour: 9, minute: 48)
        let wifiShot = "Desktop/" + screenshotName(wifiDate)
        screenshot(title: "Messages", accent: 0x34c759, lines: [
            ("Guest Wi-Fi", 40, .bold),
            ("Network: Sunrise_Cafe_Guest", 28, .semibold),
            ("Password: latte-art-2026", 28, .semibold),
            ("Ask at the counter if it doesn't connect.", 22, .regular),
        ], to: f.prepare(wifiShot))
        f.date(wifiShot, wifiDate)

        // Old screenshots, months ago.
        for (i, item) in [("Order confirmed", "Order #A1937 has shipped"), ("Masala chai recipe", "Ginger, cardamom, black tea, milk"),
                          ("Train ticket", "Mumbai → Pune · Coach C4 · Seat 22"), ("Storage almost full", "Your disk is almost full")].enumerated() {
            let date = daysAgo(Double(120 + i * 35), hour: 14 + i, minute: 10 + i * 7)
            let name = "Desktop/" + screenshotName(date)
            screenshot(title: item.0, accent: 0x8e8e93, lines: [(item.0, 40, .bold), (item.1, 26, .regular)], to: f.prepare(name))
            f.date(name, date)
        }

        // Photos.
        for i in 0..<8 {
            let name = "Pictures/Goa trip/IMG_\(2041 + i).jpg"
            photo(seed: i, to: f.prepare(name))
            f.date(name, daysAgo(Double(2 + i / 3), hour: 9 + i, minute: 15))
        }
        photo(seed: 5, to: f.prepare("Pictures/Sunset at the beach.jpg"))
        f.date("Pictures/Sunset at the beach.jpg", daysAgo(40, hour: 18, minute: 30))
        photo(seed: 3, to: f.prepare("Pictures/Weekend hike.jpg"))
        f.date("Pictures/Weekend hike.jpg", daysAgo(75, hour: 8, minute: 5))
        // A photo saved twice.
        f.copy("Pictures/Goa trip/IMG_2043.jpg", to: "Downloads/IMG_2043 (1).jpg")
        f.date("Downloads/IMG_2043 (1).jpg", daysAgo(2, hour: 20))

        // PDFs.
        pdf(title: "Q3 Report", subtitle: "Prepared by the Operations team · October 2026", paragraphs: lorem,
            chart: true, pages: 4, to: f.prepare("Documents/Q3 Report.pdf"))
        f.date("Documents/Q3 Report.pdf", daysAgo(5, hour: 15))
        f.copy("Documents/Q3 Report.pdf", to: "Downloads/Q3 Report (1).pdf")
        f.date("Downloads/Q3 Report (1).pdf", daysAgo(4, hour: 10))
        pdf(title: "Invoice March 2026", subtitle: "Bright Studio · Invoice #2031", paragraphs: Array(lorem.prefix(2)),
            pages: 1, to: f.prepare("Documents/Invoice March 2026.pdf"))
        f.date("Documents/Invoice March 2026.pdf", daysAgo(4, hour: 12))
        pdf(title: "Lease Agreement", subtitle: "12-month residential lease · Draft for signature", paragraphs: lorem,
            pages: 6, to: f.prepare("Documents/Lease agreement.pdf"))
        f.date("Documents/Lease agreement.pdf", daysAgo(62, hour: 17))
        f.copy("Documents/Lease agreement.pdf", to: "Documents/Lease agreement copy.pdf")
        f.date("Documents/Lease agreement copy.pdf", daysAgo(61, hour: 9))
        pdf(title: "Tax Return 2025", subtitle: "Summary for filing", paragraphs: lorem, pages: 3,
            to: f.prepare("Documents/Tax return 2025.pdf"))
        f.date("Documents/Tax return 2025.pdf", daysAgo(210, hour: 11))
        pdf(title: "Boarding Pass", subtitle: "Skyline Air · SK 342 · BLR → GOI", paragraphs: [lorem[3]], pages: 1,
            to: f.prepare("Downloads/Boarding pass SK342.pdf"))
        f.date("Downloads/Boarding pass SK342.pdf", daysAgo(3, hour: 7))
        f.source("Downloads/Boarding pass SK342.pdf", "https://checkin.skyline-air.example/pass/QX7P2L")

        // Other documents.
        f.text("Documents/Budget 2026.csv", "Month,Income,Expenses\nJanuary,4200,3100\nFebruary,4200,2950\nMarch,4350,3300\n")
        f.date("Documents/Budget 2026.csv", daysAgo(12, hour: 21))
        f.text("Documents/Meeting notes.txt", "Planning meeting\n\n- Launch date\n- Pricing: $5.99 once\n- Screenshots\n")
        f.date("Documents/Meeting notes.txt", daysAgo(6, hour: 16))
        f.text("Documents/Packing list.txt", "Passport\nCharger\nSunscreen\nCamera\n")
        f.date("Documents/Packing list.txt", daysAgo(4, hour: 22))

        // Downloads: installers and archives, some forgotten for months.
        f.sparse("Downloads/PhotoEditor-3.1.dmg", megabytes: 186.4)
        f.date("Downloads/PhotoEditor-3.1.dmg", daysAgo(150), lastOpened: daysAgo(150))
        f.source("Downloads/PhotoEditor-3.1.dmg", "https://downloads.pixelcraft.io/mac/PhotoEditor-3.1.dmg")
        f.sparse("Downloads/VideoConverter-Setup.pkg", megabytes: 94.2)
        f.date("Downloads/VideoConverter-Setup.pkg", daysAgo(200), lastOpened: daysAgo(199))
        f.source("Downloads/VideoConverter-Setup.pkg", "https://get.convertly.app/mac")
        f.sparse("Downloads/Project assets.zip", megabytes: 412.7)
        f.date("Downloads/Project assets.zip", daysAgo(130))
        f.source("Downloads/Project assets.zip", "https://share.cloudbox.app/s/7f2k")
        f.sparse("Downloads/Brand kit.zip", megabytes: 63.8)
        f.date("Downloads/Brand kit.zip", daysAgo(8))
        f.source("Downloads/Brand kit.zip", "https://files.pixelcraft.io/kits/brand.zip")
        f.sparse("Downloads/Conference talk.mp4", megabytes: 1_240.5)
        f.date("Downloads/Conference talk.mp4", daysAgo(160))
        f.source("Downloads/Conference talk.mp4", "https://media.devsummit.example/talks/42.mp4")

        // Movies and music.
        f.sparse("Movies/Goa trip.mov", megabytes: 2_431.6)
        f.date("Movies/Goa trip.mov", daysAgo(2, hour: 21))
        f.sparse("Movies/Screen recording.mov", megabytes: 862.3)
        f.date("Movies/Screen recording.mov", daysAgo(20, hour: 14))
        f.sparse("Music/Morning playlist.mp3", megabytes: 8.4)
        f.date("Music/Morning playlist.mp3", daysAgo(30))
        f.sparse("Music/Podcast episode 12.mp3", megabytes: 54.1)
        f.date("Music/Podcast episode 12.mp3", daysAgo(14))

        // Folders get today's date otherwise; keep them tidy.
        for folder in ["Desktop", "Documents", "Downloads", "Pictures", "Pictures/Goa trip", "Movies", "Music"] {
            f.date(folder, daysAgo(1))
        }
        print("Wrote demo folder to \(root.path)")
    }
}
