#if FILEWISE_SNAPSHOT
import AppKit
import FilewiseCore
import ApplicationServices

/// Development-only UI capture. Compiled solely by scripts/snapshot-ui.sh
/// (with -D FILEWISE_SNAPSHOT); never part of the shipping app. It renders the
/// window from inside the process, so no Screen Recording permission is needed.
@MainActor
enum SnapshotHook {
    static weak var library: Library?
    static weak var store: Store?

    static func install() {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["FILEWISE_SNAPSHOT_DIR"], let folder = env["FILEWISE_SNAPSHOT_FOLDER"] else { return }
        let appearance = env["FILEWISE_SNAPSHOT_APPEARANCE"] ?? "light"
        // Each step is name:category[:query][:select|play|scroll|scroll2|end]; category "Paywall" captures the
        // unlock sheet, category "Settings" captures the
        // Settings window, and a first step with category "Welcome" captures the first-run page.
        let steps = (env["FILEWISE_SNAPSHOT_STEPS"] ?? "home:Home").split(separator: ",").map(String.init)
        Task {
            try? await Task.sleep(for: .seconds(1))
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            // FILEWISE_SNAPSHOT_WIDTH sets the window width, e.g. 860 to check the narrowest layout.
            if let width = env["FILEWISE_SNAPSHOT_WIDTH"].flatMap(Double.init),
               let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) {
                var frame = window.frame
                frame.size.width = width
                window.setFrame(frame, display: true)
            }
            var steps = steps
            if let first = steps.first, first.split(separator: ":").dropFirst().first == "Welcome" {
                try? await Task.sleep(for: .milliseconds(1500))
                let fields = first.split(separator: ":").map(String.init)
                let name = fields.first ?? "welcome"
                if fields.count > 2, fields[2] == "ax" {
                    writeAccessibility(name, output: URL(fileURLWithPath: output), appearance: appearance)
                } else {
                    capture(to: URL(fileURLWithPath: output).appendingPathComponent("\(name)-\(appearance).png"))
                }
                steps.removeFirst()
            }
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
            if parts.count > 1, parts[1] == "Paywall", let store {
                // The unlock sheet: the one already shown by itself when the trial
                // has ended, or else as shown for the Clean Up suggestions.
                if store.paywall == nil {
                    let suggestions = library.summary(for: "Clean Up")
                    store.paywall = PaywallRequest(bytes: suggestions.bytes, count: suggestions.count)
                }
                try? await Task.sleep(for: .milliseconds(1500))
                let sheet = NSApp.windows.first { $0.isVisible && $0.isSheet }
                if parts.count > 2, parts[2] == "ax" {
                    writeAccessibility(parts[0], output: output, appearance: appearance)
                } else {
                    capture(to: output.appendingPathComponent("\(parts[0])-\(appearance).png"), window: sheet)
                }
                store.paywall = nil
                try? await Task.sleep(for: .milliseconds(600))
                continue
            }
            if parts.count > 1, parts[1] == "Accessibility" {
                // What VoiceOver can reach in a view: name:Accessibility:<category>.
                library.query = ""
                library.category = parts.count > 2 && !parts[2].isEmpty ? parts[2] : "Home"
                try? await Task.sleep(for: .milliseconds(1500))
                // Asks this app through the same API VoiceOver uses, which makes
                // SwiftUI build its accessibility tree.
                writeAccessibility(parts[0], output: output, appearance: appearance)
                continue
            }
            if parts.count > 1, parts[1] == "Settings" {
                // ⌘, through the app menu, as a user would open it.
                let comma = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                             windowNumber: 0, context: nil, characters: ",",
                                             charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)
                if let comma { _ = NSApp.mainMenu?.performKeyEquivalent(with: comma) }
                try? await Task.sleep(for: .milliseconds(1500))
                let settings = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true }
                    ?? NSApp.windows.first { $0.isVisible && $0.title.localizedCaseInsensitiveContains("settings") }
                if parts.count > 2, parts[2] == "ax" {
                    writeAccessibility(parts[0], output: output, appearance: appearance)
                } else {
                    capture(to: output.appendingPathComponent("\(parts[0])-\(appearance).png"), window: settings)
                }
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
                case "end": scrollDown(toEnd: true)
                case "scroll2": scrollDown(); scrollDown()
                default: library.selectedIDs = [first.id]
                }
            }
            try? await Task.sleep(for: .milliseconds(1200))
            capture(to: output.appendingPathComponent("\(parts[0])-\(appearance).png"))
        }
    }

    /// Writes what VoiceOver can reach in the app to <name>-<appearance>.txt.
    private static func writeAccessibility(_ name: String, output: URL, appearance: String) {
        var lines: [String] = []
        dumpAX(AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier), depth: 0, into: &lines)
        try? lines.joined(separator: "\n")
            .write(to: output.appendingPathComponent("\(name)-\(appearance).txt"), atomically: true, encoding: .utf8)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// One line per element as VoiceOver sees it: role, description or title,
    /// value, and actions. "!" marks buttons and images without a name.
    private static func dumpAX(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 60 else { return }
        let role = attribute(element, kAXRoleAttribute) as? String ?? "?"
        // The system menu bar lists the user's recent items; it is not the app's UI.
        if role == kAXMenuBarRole { return }
        let name = [kAXDescriptionAttribute, kAXTitleAttribute, kAXLabelValueAttribute]
            .compactMap { attribute(element, $0) as? String }.first { !$0.isEmpty } ?? ""
        let value = attribute(element, kAXValueAttribute).map { "\($0)" } ?? ""
        var actionNames: CFArray?
        AXUIElementCopyActionNames(element, &actionNames)
        let actions = ((actionNames as? [String]) ?? []).filter { !$0.hasPrefix("AX") || $0 == "AXShowMenu" }
            .map { $0.components(separatedBy: "\n").first { $0.hasPrefix("Name:") }?.dropFirst(5).description ?? $0 }
        let unnamed = (role == kAXButtonRole || role == kAXImageRole) && name.isEmpty
        var line = (unnamed ? "! " : "  ") + String(repeating: "  ", count: min(depth, 24)) + role
        if !name.isEmpty { line += " \"\(name)\"" }
        if !value.isEmpty, value != name, !value.hasPrefix("<") { line += " = \(value.prefix(60))" }
        if !actions.isEmpty { line += " [\(actions.joined(separator: ", "))]" }
        lines.append(line)
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            dumpAX(child, depth: depth + 1, into: &lines)
        }
    }

    /// One line per accessibility element: role, label or title, value, and
    /// custom actions. Lines starting with "!" are buttons VoiceOver cannot name.
    private static func dumpAccessibility(_ element: Any, depth: Int, into lines: inout [String]) {
        guard depth < 60, let node = element as? NSAccessibilityProtocol else { return }
        if node.isAccessibilityElement() {
            let role = node.accessibilityRole()?.rawValue ?? "?"
            let name = [node.accessibilityLabel(), node.accessibilityTitle()]
                .compactMap { $0 }.first { !$0.isEmpty } ?? ""
            let value = (node.accessibilityValue()).map { "\($0)" } ?? ""
            let actions = (node.accessibilityCustomActions() ?? []).map(\.name)
            let unnamed = role == NSAccessibility.Role.button.rawValue && name.isEmpty
            var line = (unnamed ? "! " : "  ") + String(repeating: "  ", count: min(depth, 20)) + role
            if !name.isEmpty { line += " \"\(name)\"" }
            if !value.isEmpty, value != name { line += " = \(value.prefix(60))" }
            if !actions.isEmpty { line += " [\(actions.joined(separator: ", "))]" }
            lines.append(line)
        }
        for child in node.accessibilityChildren() ?? [] {
            dumpAccessibility(child, depth: depth + 1, into: &lines)
        }
    }

    /// Scrolls the largest scroll view (the page) down by most of its height,
    /// or to the bottom.
    private static func scrollDown(toEnd: Bool = false) {
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
        }
        guard let content = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 })?.contentView,
              let page = scrollViews(in: content).max(by: { $0.frame.height * $0.frame.width < $1.frame.height * $1.frame.width })
        else { return }
        let clip = page.contentView
        let bottom = (page.documentView?.frame.height ?? 0) - clip.bounds.height
        clip.scroll(to: NSPoint(x: 0, y: toEnd ? max(0, bottom) : clip.bounds.origin.y + clip.bounds.height * 0.75))
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
