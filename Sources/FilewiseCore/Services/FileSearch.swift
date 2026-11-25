import Foundation

/// Filters indexed files by sidebar category and by a search phrase such as
/// "pdfs from last week" or "large videos". Name terms use the SQLite search
/// index when it covers `folder`, and an equivalent in-memory match otherwise.
public enum FileSearch {
    public static let defaultSortOrder = [KeyPathComparator(\FileItem.modified, order: .reverse)]

    /// - Parameter files: Newest first, as produced by a scan.
    public static func filter(_ files: [FileItem], query: String, category: String, folder: URL?,
                              sortOrder: [KeyPathComparator<FileItem>] = defaultSortOrder,
                              now: Date = Date()) -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let dateRange = dateFilter(in: trimmed, now: now)?.range
        let recent = words.contains("recent")
        let wantsPDF = words.contains("pdf") || words.contains("pdfs")
        let wantsVideos = words.contains("video") || words.contains("videos")
        let wantsScreenshots = words.contains { word in
            word.hasPrefix("screenshot") || screenshotAliases.contains(word)
        }
        let wantsDownloads = words.contains("downloads") || words.contains("download")
        let wantsLarge = words.contains("large")
        let wantsDuplicates = words.contains { duplicateAliases.contains($0) }
        var ignored = Set(["find", "show", "me", "my", "from", "in", "the", "a", "recent", "files", "file", "pdf", "pdfs", "video", "videos", "downloads", "download", "large", "of", "since", "during"])
        ignored.formUnion(dateWords)
        ignored.formUnion(duplicateAliases)
        ignored.formUnion(screenshotAliases)
        let terms = words.filter { !ignored.contains($0) }
        let foldedTerms = terms.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let ftsMatchedPaths = terms.isEmpty ? nil : FileIndex.searchPaths(terms: terms, root: folder)
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        var result = files.filter { item in
            (trimmed.isEmpty ? matches(item, category: category, recentCutoff: recentCutoff) : true)
                && (!wantsPDF || item.kind == "pdf")
                && (!wantsVideos || item.libraryCategory == "Videos")
                && (!wantsScreenshots || item.isScreenshot)
                && (!wantsDownloads || item.isDownload)
                && (!wantsLarge || item.isLarge)
                && (!wantsDuplicates || item.duplicate)
                && (dateRange.map { $0.contains(item.modified) } ?? true)
                && (!recent || item.modified >= recentCutoff)
                && (terms.isEmpty || (ftsMatchedPaths.map { $0.contains(item.url.path) }
                    ?? matchesWordPrefixes(item, terms: foldedTerms)))
        }
        // `files` is already newest first, so only other orders need sorting.
        if sortOrder != defaultSortOrder {
            result.sort(using: sortOrder)
        }
        return result
    }

    private static let screenshotAliases: Set<String> = [
        "screenshot", "screenshots", "screesnhot", "screesnshots",
        "screnshot", "screnshots", "screen", "screens"
    ]
    private static let duplicateAliases: Set<String> = ["duplicate", "duplicates", "dupe", "dupes"]
    private static let dateWords: Set<String> = ["today", "yesterday", "this", "last", "past", "week", "month"]

    /// A date phrase found in a search, such as "last week".
    public struct DateFilter: Sendable, Equatable {
        /// The phrase as the user would say it, e.g. "from last week".
        public let phrase: String
        public let range: DateInterval
    }

    /// The date phrase in `query`, if any. "Last week" and "last month" run
    /// from the start of the previous calendar week or month up to now, so they
    /// cover both "the week before this one" and "the past seven days".
    public static func dateFilter(in query: String, now: Date = Date()) -> DateFilter? {
        let text = query.lowercased()
        let calendar = Calendar.current
        func since(_ start: Date?, _ phrase: String) -> DateFilter? {
            guard let start, start <= now else { return nil }
            return DateFilter(phrase: phrase, range: DateInterval(start: start, end: now))
        }
        func previous(_ component: Calendar.Component, _ unit: Calendar.Component) -> Date? {
            calendar.date(byAdding: unit, value: -1, to: now)
                .flatMap { calendar.dateInterval(of: component, for: $0)?.start }
        }
        if text.contains("yesterday") {
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
            return DateFilter(phrase: "from yesterday", range: DateInterval(start: start, end: today))
        }
        if text.contains("today") { return since(calendar.startOfDay(for: now), "from today") }
        if text.contains("last week") || text.contains("past week") {
            return since(previous(.weekOfYear, .weekOfYear), "from last week")
        }
        if text.contains("this week") { return since(calendar.dateInterval(of: .weekOfYear, for: now)?.start, "from this week") }
        if text.contains("last month") || text.contains("past month") {
            return since(previous(.month, .month), "from last month")
        }
        if text.contains("this month") { return since(calendar.dateInterval(of: .month, for: now)?.start, "from this month") }
        return nil
    }

    /// `query` without its date phrase, for "search all dates".
    public static func removingDate(from query: String) -> String {
        var text = query
        for phrase in ["from last week", "from past week", "from this week", "from last month", "from past month",
                       "from this month", "from today", "from yesterday", "last week", "past week", "this week",
                       "last month", "past month", "this month", "today", "yesterday"] {
            text = text.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        return text.split(separator: " ").joined(separator: " ")
    }

    private static func matches(_ item: FileItem, category: String, recentCutoff: Date) -> Bool {
        switch category {
        case "Recents": item.modified >= recentCutoff
        case "Images", "Videos", "Music", "Documents", "Archives", "Apps": item.libraryCategory == category
        case "Duplicates": item.duplicate
        case "Screenshots": item.isScreenshot
        case "Old Screenshots": item.isOldScreenshot
        case "Forgotten Downloads": item.isForgottenDownload
        case "Downloads": item.isDownload
        case "Downloaded From": item.isDownloaded
        case "Large Files": item.isLarge
        case "Clean Up": item.isCleanupCandidate
        default:
            if category.hasPrefix("Origin: ") {
                item.downloadSource == String(category.dropFirst("Origin: ".count))
            } else {
                true
            }
        }
    }

    /// In-memory equivalent of the FTS5 query, used while the search index
    /// covers a different folder: every term must begin a word in the file's
    /// name, parent folder path, or download source.
    private static func matchesWordPrefixes(_ item: FileItem, terms: [String]) -> Bool {
        let text = [item.name, item.url.deletingLastPathComponent().path, item.downloadSource ?? ""]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }
}
