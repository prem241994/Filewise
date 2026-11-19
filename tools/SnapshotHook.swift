#if FILEWISE_SNAPSHOT
import AppKit
import FilewiseCore

/// Development-only UI capture. Compiled solely by scripts/snapshot-ui.sh
/// (with -D FILEWISE_SNAPSHOT); never part of the shipping app. It renders the
/// window from inside the process, so no Screen Recording permission is needed.
@MainActor
enum SnapshotHook {
    static weak var library: Library?

    static func install() {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["FILEWISE_SNAPSHOT_DIR"], let folder = env["FILEWISE_SNAPSHOT_FOLDER"] else { return }
        let appearance = env["FILEWISE_SNAPSHOT_APPEARANCE"] ?? "light"
        // Each step is name:category[:query][:select|play|scroll]; category "Settings" captures the Settings window
        let steps = (env["FILEWISE_SNAPSHOT_STEPS"] ?? "home:Home").split(separator: ",").map(String.init)
        Task {
            try? await Task.sleep(for: .seconds(1))
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            library?.scan(URL(fileURLWithPath: folder))
            await run(steps, output: URL(fileURLWithPath: output), appearance: appearance)
            NSApp.terminate(nil)
        }
    }

    private static func run(_ steps: [String], output: URL, appearance: String) async {
        for step in steps {
            while library == nil || library?.scanning == true {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let library else { return }
            let parts = step.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if parts.count > 1, parts[1] == "Settings" {
                // ⌘, through the app menu, as a user would open it.
                let comma = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                             windowNumber: 0, context: nil, characters: ",",
                                             charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)
                if let comma { _ = NSApp.mainMenu?.performKeyEquivalent(with: comma) }
                try? await Task.sleep(for: .milliseconds(1500))
                let settings = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true }
                    ?? NSApp.windows.first { $0.isVisible && $0.title.localizedCaseInsensitiveContains("settings") }
                capture(to: output.appendingPathComponent("\(parts[0])-\(appearance).png"), window: settings)
                settings?.close()
                continue
            }
            library.query = ""
            library.category = parts.count > 1 ? parts[1] : "Home"
            library.query = parts.count > 2 ? parts[2] : ""
            try? await Task.sleep(for: .milliseconds(800))
            if parts.count > 3, let first = library.visible.first ?? library.files.first {
                switch parts[3] {
                case "play": library.play(first)
                case "scroll": scrollDown()
                default: library.selectedIDs = [first.id]
                }
            }
            try? await Task.sleep(for: .milliseconds(1200))
            capture(to: output.appendingPathComponent("\(parts[0])-\(appearance).png"))
        }
    }

    /// Scrolls the largest scroll view (the page) down by most of its height.
    private static func scrollDown() {
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
        }
        guard let content = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 })?.contentView,
              let page = scrollViews(in: content).max(by: { $0.frame.height * $0.frame.width < $1.frame.height * $1.frame.width })
        else { return }
        let clip = page.contentView
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y + clip.bounds.height * 0.75))
        page.reflectScrolledClipView(clip)
    }

    private typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Uses the window server so materials and vibrancy render as on screen.
    /// An app may capture its own windows without Screen Recording permission.
    /// The API is unavailable to the current SDK, so it is resolved at runtime.
    private static func capture(to url: URL, window chosen: NSWindow? = nil) {
        guard let window = chosen ?? NSApp.windows.filter({ $0.isVisible && $0.contentView != nil })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return }
        var image: CGImage?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let create = unsafeBitCast(symbol, to: WindowImage.self)
            // .optionIncludingWindow, .boundsIgnoreFraming | .bestResolution
            image = create(.null, 1 << 3, UInt32(window.windowNumber), 1 | 1 << 3)?.takeRetainedValue()
        }
        if let image {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        } else if let view = window.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
#endif
