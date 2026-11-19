import FilewiseCore
import Foundation

/// Checks which copy each keep rule leaves unselected. Pure logic: no files
/// are created and no index is used.
@main struct DuplicateSelectionHarness {
    static func item(_ path: String, days: Double, hash: UInt8?, duplicate: Bool = true) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), size: 10,
                 modified: Date(timeIntervalSince1970: 1_700_000_000 + days * 86_400), changed: nil,
                 duplicate: duplicate, hash: hash.map { Data(repeating: $0, count: 32) }, downloadSource: nil)
    }

    static func main() {
        let original = item("/lib/Documents/Plan.pdf", days: 5, hash: 1)
        let copy = item("/lib/Downloads/Plan copy.pdf", days: 1, hash: 1)
        let newest = item("/lib/Desktop/Plan (2).pdf", days: 9, hash: 1)
        let photo = item("/lib/Photos/Holiday.jpg", days: 3, hash: 2)
        let photoCopy = item("/lib/Downloads/Holiday (1).jpg", days: 3, hash: 2)  // same date: path breaks the tie
        let unique = item("/lib/Documents/Notes.txt", days: 2, hash: 3, duplicate: false)
        let files = [original, copy, newest, photo, photoCopy, unique]

        func extras(_ rule: KeepRule) -> Set<String> { DuplicateSelection.extraCopies(in: files, keeping: rule) }

        precondition(DuplicateSelection.groups(in: files).count == 2, "expected two duplicate groups")
        precondition(extras(.oldest) == [original.id, newest.id, photo.id], "oldest rule kept the wrong copies")
        precondition(extras(.newest) == [original.id, copy.id, photo.id], "newest rule kept the wrong copies (or broke a date tie by scan order)")
        precondition(extras(.shortestName) == [copy.id, newest.id, photoCopy.id], "shortest-name rule kept the wrong copies")
        precondition(extras(.inFolder("/lib/Documents")) == [copy.id, newest.id, photo.id],
                     "folder rule did not keep the Documents copy, or mishandled a group with no copy there")
        precondition(!extras(.oldest).contains(unique.id), "a unique file was selected")
        for rule in [KeepRule.oldest, .newest, .shortestName, .inFolder("/lib/Documents")] {
            // Exactly one file per group stays unselected.
            precondition(extras(rule).count == 3, "\(rule) did not leave one file per group")
            precondition(KeepRule(rawValue: rule.rawValue) == rule, "\(rule) did not round-trip through preferences")
        }
        precondition(KeepRule(rawValue: "folder:") == nil && KeepRule(rawValue: "bogus") == nil, "invalid rules were accepted")
        precondition(DuplicateSelection.foldersWithDuplicates(in: files).first == "/lib/Downloads",
                     "folders were not ordered by number of duplicates")
        print("PASS: duplicate keep rules")
    }
}
