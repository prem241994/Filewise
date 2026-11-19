import Foundation

public enum FileUsage {
    /// The attribute macOS writes when a file is opened from Finder or an app:
    /// a 16-byte timespec (seconds, then nanoseconds, little-endian).
    public static let lastUsedAttribute = "com.apple.lastuseddate#PS"

    /// When the file was last opened, if macOS has recorded it.
    public static func lastOpened(for url: URL) -> Date? {
        var bytes = [UInt8](repeating: 0, count: 16)
        let length = getxattr(url.path, lastUsedAttribute, &bytes, bytes.count, 0, 0)
        guard length == 16 else { return nil }
        let seconds = bytes[0..<8].reversed().reduce(Int64(0)) { $0 << 8 | Int64($1) }
        let nanoseconds = bytes[8..<16].reversed().reduce(Int64(0)) { $0 << 8 | Int64($1) }
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
    }
}
