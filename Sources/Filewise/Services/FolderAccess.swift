import AppKit
import Darwin

/// Folder access for the App Sandbox. A sandboxed app may only read folders
/// the user chose in an open panel or dropped on the window (plus Downloads,
/// through its entitlement). Each granted folder is kept as a security-scoped
/// bookmark so it can be reopened after relaunch. Outside the sandbox (tests,
/// the snapshot build) every folder is accessible and nothing is asked.
@MainActor
enum FolderAccess {
    private static let bookmarksKey = "filewise.folderBookmarks"

    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// The user's real home folder. Inside the sandbox `NSHomeDirectory()` and
    /// `FileManager.urls(for:in:)` point into the app's container instead.
    static let homeDirectory: URL = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Saves access to a folder the user just granted (open panel or drop).
    static func remember(_ url: URL) {
        guard isSandboxed, let data = try? url.bookmarkData(options: [.withSecurityScope]) else { return }
        var bookmarks = storedBookmarks
        bookmarks[url.standardizedFileURL.path] = data
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    /// A URL for `path` that the app can open, or nil if the user has not
    /// granted access. The URL is security-scoped when it came from a bookmark,
    /// so the caller must call `startAccessingSecurityScopedResource()` on it.
    static func url(forPath path: String) -> URL? {
        let plain = URL(fileURLWithPath: path, isDirectory: true)
        guard isSandboxed else { return plain }
        var bookmarks = storedBookmarks
        if let data = bookmarks[path] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale || url.standardizedFileURL.path != path {
                    // The folder moved or the bookmark needs refreshing.
                    bookmarks[path] = nil
                    let refreshed = url.startAccessingSecurityScopedResource()
                    if let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                        bookmarks[url.standardizedFileURL.path] = fresh
                    }
                    if refreshed { url.stopAccessingSecurityScopedResource() }
                    UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
                }
                return url
            }
            // The folder no longer exists or its bookmark cannot be read.
            bookmarks[path] = nil
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        }
        // Downloads is readable through its entitlement without a bookmark.
        return isReadable(plain) ? plain : nil
    }

    /// A URL for `url` that the app can open: the URL itself when it is already
    /// readable (a dropped folder, Downloads), a saved bookmark, or else the
    /// folder the user grants in an open panel. Nil if they cancel.
    static func grantedURL(for url: URL) -> URL? {
        guard isSandboxed else { return url }
        if isReadable(url) {
            remember(url)
            return url
        }
        return self.url(forPath: url.standardizedFileURL.path) ?? requestAccess(to: url)
    }

    /// Asks the user to grant access to `url` with an open panel that starts
    /// there. Returns the folder they chose, which may be a different one.
    static func requestAccess(to url: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.message = "Filewise needs your permission to read “\(url.lastPathComponent)”. Click Allow Access to scan it."
        panel.prompt = "Allow Access"
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        remember(chosen)
        return chosen
    }

    private static var storedBookmarks: [String: Data] {
        UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }

    private static func isReadable(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }
}
