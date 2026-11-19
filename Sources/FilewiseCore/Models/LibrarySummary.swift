import Foundation

public struct LibrarySummary: Sendable {
    public var count = 0
    public var bytes: Int64 = 0

    public init() {}

    public mutating func add(_ item: FileItem) {
        count += 1
        bytes += item.size
    }

    /// Totals for every sidebar and dashboard category, plus totals per
    /// download source.
    public static func totals(for items: [FileItem], now: Date = Date())
        -> (categories: [String: LibrarySummary], sources: [String: LibrarySummary]) {
        var totals: [String: LibrarySummary] = [:]
        var sources: [String: LibrarySummary] = [:]
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        for item in items {
            totals["Home", default: LibrarySummary()].add(item)
            if let category = item.libraryCategory { totals[category, default: LibrarySummary()].add(item) }
            if item.modified >= recentCutoff { totals["Recents", default: LibrarySummary()].add(item) }
            if item.isScreenshot { totals["Screenshots", default: LibrarySummary()].add(item) }
            if item.isOldScreenshot { totals["Old Screenshots", default: LibrarySummary()].add(item) }
            if item.isDownload { totals["Downloads", default: LibrarySummary()].add(item) }
            if item.isDownloaded { totals["Downloaded From", default: LibrarySummary()].add(item) }
            if item.isForgottenDownload { totals["Forgotten Downloads", default: LibrarySummary()].add(item) }
            if item.isLarge { totals["Large Files", default: LibrarySummary()].add(item) }
            if item.duplicate { totals["Duplicates", default: LibrarySummary()].add(item) }
            if item.isCleanupCandidate { totals["Clean Up", default: LibrarySummary()].add(item) }
            if let source = item.downloadSource { sources[source, default: LibrarySummary()].add(item) }
        }
        return (totals, sources)
    }
}
