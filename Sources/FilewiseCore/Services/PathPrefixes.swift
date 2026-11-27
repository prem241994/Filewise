import Foundation

public enum PathPrefixes {
    /// A folder's path in every form other code may report it, each ending in
    /// "/": as given, canonical (symlinks resolved, e.g. /private/var/…), and
    /// canonical without the /private prefix (/var/…), which is how
    /// `URL.resolvingSymlinksInPath()` reports it. FSEvents and the scanner
    /// report canonical paths, so matching must accept all of them.
    public static func forFolder(_ url: URL) -> [String] {
        let canonical: String? = url.path.withCString { path in
            guard let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        var forms = [url.standardizedFileURL.path, canonical ?? url.path]
        if let canonical, canonical.hasPrefix("/private/") {
            forms.append(String(canonical.dropFirst("/private".count)))
        }
        return Array(Set(forms)).map { $0 == "/" || $0.hasSuffix("/") ? $0 : $0 + "/" }
    }
}
