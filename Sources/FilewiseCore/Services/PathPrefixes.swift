import Foundation

public enum PathPrefixes {
    /// A folder's path, plus its canonical form when they differ (for example
    /// /var and /private/var), each ending in "/". FSEvents and some file APIs
    /// report canonical paths, so matching must accept both.
    public static func forFolder(_ url: URL) -> [String] {
        let canonical: String? = url.path.withCString { path in
            guard let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return Array(Set([url.standardizedFileURL.path, canonical ?? url.path]))
            .map { $0 == "/" || $0.hasSuffix("/") ? $0 : $0 + "/" }
    }
}
