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
        let lastWeek = trimmed.localizedCaseInsensitiveContains("last week")
        let recent = words.contains("recent")
        let wantsPDF = words.contains("pdf") || words.contains("pdfs")
        let wantsVideos = words.contains("video") || words.contains("videos")
        let screenshotAliases: Set<String> = [
            "screenshot", "screenshots", "screesnhot", "screesnshots",
            "screnshot", "screnshots", "screen", "screens"
        ]
        let wantsScreenshots = words.contains { word in
            word.hasPrefix("screenshot") || screenshotAliases.contains(word)
        }
        let wantsDownloads = words.contains("downloads") || words.contains("download")
        let wantsLarge = words.contains("large")
        let duplicateAliases: Set<String> = ["duplicate", "duplicates", "dupe", "dupes"]
        let wantsDuplicates = words.contains { duplicateAliases.contains($0) }
        var ignored = Set(["find", "show", "me", "my", "from", "in", "the", "a", "last", "week", "recent", "files", "file", "pdf", "pdfs", "video", "videos", "downloads", "download", "large"])
        ignored.formUnion(duplicateAliases)
        ignored.formUnion(screenshotAliases)
        let terms = words.filter { !ignored.contains($0) }
        let foldedTerms = terms.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let ftsMatchedPaths = terms.isEmpty ? nil : FileIndex.searchPaths(terms: terms, root: folder)
        let calendar = Calendar.current
        let previousWeek = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now)
        let recentCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        var result = files.filter { item in
            (trimmed.isEmpty ? matches(item, category: category, recentCutoff: recentCutoff) : true)
                && (!wantsPDF || item.kind == "pdf")
                && (!wantsVideos || item.libraryCategory == "Videos")
                && (!wantsScreenshots || item.isScreenshot)
                && (!wantsDownloads || item.isDownload)
                && (!wantsLarge || item.isLarge)
                && (!wantsDuplicates || item.duplicate)
                && (!lastWeek || (previousWeek?.contains(item.modified) ?? false))
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

    private static func matches(_ item: FileItem, category: String, recentCutoff: Date) -> Bool {
        switch category {
        case "Recents": item.modified >= recentCutoff
        case "Images", "Videos", "Music", "Documents", "Archives", "Apps": item.libraryCategory == category
        case "Duplicates": item.duplicate
        case "Screenshots": item.isScreenshot
        case "Old Screenshots": item.isOldScreenshot
        case "Forgotten Downloads": item.isForgottenDownload
        case "Downloads": item.isDownload
        case "Downloaded From": item.downloadSource != nil || item.isDownload
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
