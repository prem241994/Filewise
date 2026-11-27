import Foundation

/// Which file to keep from each group of identical files.
public enum KeepRule: Hashable, Sendable {
    case oldest
    case newest
    /// Usually the original: "Plan.pdf" rather than "Plan copy.pdf".
    case shortestName
    /// The copy inside this folder (a full path), when a group has one.
    case inFolder(String)

    /// A stable string for saving the choice in preferences.
    public var rawValue: String {
        switch self {
        case .oldest: "oldest"
        case .newest: "newest"
        case .shortestName: "shortestName"
        case .inFolder(let path): "folder:" + path
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "oldest": self = .oldest
        case "newest": self = .newest
        case "shortestName": self = .shortestName
        default:
            guard rawValue.hasPrefix("folder:"), rawValue.count > "folder:".count else { return nil }
            self = .inFolder(String(rawValue.dropFirst("folder:".count)))
        }
    }

    /// Completes "keeping the … in each group".
    public var summary: String {
        switch self {
        case .oldest: "oldest copy"
        case .newest: "newest copy"
        case .shortestName: "copy with the shortest name"
        case .inFolder(let path): "copy in \(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }
}

public enum DuplicateSelection {
    /// Groups of two or more identical files. Files without a hash are grouped
    /// by size and name, as a cautious fallback.
    public static func groups(in files: [FileItem]) -> [[FileItem]] {
        Dictionary(grouping: files.filter(\.duplicate)) { item -> String in
            if let hash = item.hash { return hash.map { String(format: "%02hhx", $0) }.joined() }
            return "\(item.size)_\(item.name)"
        }
        .values
        .filter { $0.count > 1 }
    }

    /// The file `rule` keeps from a group. Ties fall back to the oldest file,
    /// then to the path, so the choice never depends on scan order.
    public static func keeper(of group: [FileItem], rule: KeepRule) -> FileItem? {
        // Both forms of the chosen folder's path (/var and /private/var), worked
        // out once rather than on every comparison.
        var folderPrefixes: [String] = []
        if case .inFolder(let path) = rule { folderPrefixes = PathPrefixes.forFolder(URL(fileURLWithPath: path)) }
        return group.min { a, b in
            switch rule {
            case .oldest:
                break
            case .newest:
                if a.modified != b.modified { return a.modified > b.modified }
            case .shortestName:
                if a.name.count != b.name.count { return a.name.count < b.name.count }
            case .inFolder:
                let aInside = folderPrefixes.contains(where: a.url.path.hasPrefix)
                let bInside = folderPrefixes.contains(where: b.url.path.hasPrefix)
                if aInside != bInside { return aInside }
            }
            if a.modified != b.modified { return a.modified < b.modified }
            return a.url.path < b.url.path
        }
    }

    /// Every duplicate except the one `rule` keeps in each group.
    public static func extraCopies(in files: [FileItem], keeping rule: KeepRule) -> Set<String> {
        var extras = Set<String>()
        for group in groups(in: files) {
            guard let keep = keeper(of: group, rule: rule) else { continue }
            extras.formUnion(group.lazy.filter { $0.id != keep.id }.map(\.id))
        }
        return extras
    }

    /// Folders that hold at least one duplicate, for offering "keep the copy
    /// in this folder"; most duplicates first.
    public static func foldersWithDuplicates(in files: [FileItem]) -> [String] {
        var counts: [String: Int] = [:]
        for group in groups(in: files) {
            for item in group { counts[item.url.deletingLastPathComponent().path, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}
