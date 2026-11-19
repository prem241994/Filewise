import Foundation
import os

/// User-adjustable limits for cleanup suggestions, and folders to skip.
public struct CleanupSettings: Sendable, Equatable {
    public static let defaultLargeFileBytes: Int64 = 100_000_000
    public static let defaultOldAfterDays = 30

    /// Files at least this size are suggested as large.
    public var largeFileBytes: Int64
    /// Screenshots and downloads unused for this many days are suggested as old.
    public var oldAfterDays: Int
    /// Full paths of folders that scans skip, including everything inside.
    public var ignoredFolders: [String]

    public init(largeFileBytes: Int64 = defaultLargeFileBytes, oldAfterDays: Int = defaultOldAfterDays,
                ignoredFolders: [String] = []) {
        self.largeFileBytes = largeFileBytes
        self.oldAfterDays = oldAfterDays
        self.ignoredFolders = ignoredFolders
    }

    private static let storage = OSAllocatedUnfairLock(initialState: CleanupSettings())

    /// The settings in effect, readable from any thread. The app sets this
    /// from its preferences; tests set it directly.
    public static var current: CleanupSettings {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// The date before which a screenshot or download counts as old.
    public func oldCutoff(now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -oldAfterDays, to: now) ?? now
    }

    /// Paths, in both their given and canonical forms, of folders to skip.
    public var ignoredPaths: Set<String> {
        Set(ignoredFolders.flatMap { PathPrefixes.forFolder(URL(fileURLWithPath: $0)) }
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
    }
}
