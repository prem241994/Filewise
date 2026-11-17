#if FILEWISE_SNAPSHOT
import AppKit

/// Development-only UI capture. Compiled solely by scripts/snapshot-ui.sh
/// (with -D FILEWISE_SNAPSHOT); never part of the shipping app. It renders the
/// window from inside the process, so no Screen Recording permission is needed.
enum SnapshotHook {
    static weak var library: Library?

    static func install() {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["FILEWISE_SNAPSHOT_DIR"], let folder = env["FILEWISE_SNAPSHOT_FOLDER"] else { return }
        let appearance = env["FILEWISE_SNAPSHOT_APPEARANCE"] ?? "light"
        // Each step is name:category[:query][:select]
        let steps = (env["FILEWISE_SNAPSHOT_STEPS"] ?? "home:Home").split(separator: ",").map(String.init)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            library?.scan(URL(fileURLWithPath: folder))
            run(steps, output: URL(fileURLWithPath: output), appearance: appearance)
        }
    }

    private static func run(_ steps: [String], output: URL, appearance: String) {
        guard let library, !library.scanning else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { run(steps, output: output, appearance: appearance) }
            return
        }
        guard let step = steps.first else { NSApp.terminate(nil); return }
        let parts = step.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        library.query = ""
        library.category = parts.count > 1 ? parts[1] : "Home"
        library.query = parts.count > 2 ? parts[2] : ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if parts.count > 3, parts[3] == "select", let first = library.visible.first ?? library.files.first {
                library.selectedIDs = [first.id]
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                capture(to: output.appendingPathComponent("\(parts[0])-\(appearance).png"))
                run(Array(steps.dropFirst()), output: output, appearance: appearance)
            }
        }
    }

    private typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Uses the window server so materials and vibrancy render as on screen.
    /// An app may capture its own windows without Screen Recording permission.
    /// The API is unavailable to the current SDK, so it is resolved at runtime.
    private static func capture(to url: URL) {
        guard let window = NSApp.windows.filter({ $0.isVisible && $0.contentView != nil })
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
