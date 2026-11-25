import FilewiseCore
import Foundation

/// Checks the date phrases in searches ("last week", "today", …) against a
/// fixed "now", with weeks starting on Monday and on Sunday.
@main
struct SearchDatesHarness {
    static func main() {
        do {
            try run()
            print("PASS: search date phrases, ranges, date removal, and screenshot filtering by date")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    static func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    static func screenshot(_ name: String, _ modified: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/tmp/filewise-dates/\(name)"), size: 10, modified: date(modified),
                 changed: nil, duplicate: false, hash: nil, downloadSource: nil)
    }

    static func run() throws {
        // Wednesday 25 November 2026, 9 PM.
        let now = date("2026-11-25 21:00")

        // "Last week" reaches back to the start of the previous calendar week
        // (Sunday 15 or Monday 16 November, depending on the locale) and runs
        // up to now, so it also covers the past seven days.
        let lastWeek = try requireValue(FileSearch.dateFilter(in: "screenshots from last week", now: now))
        let start = Calendar.current.component(.day, from: lastWeek.range.start)
        try require([15, 16].contains(start) && Calendar.current.component(.month, from: lastWeek.range.start) == 11,
                    "last week started on the wrong day: \(lastWeek.range.start)")
        try require(lastWeek.range.end == now, "last week did not run up to now")
        try require(lastWeek.phrase == "from last week", "last week phrase was wrong")
        try require(FileSearch.dateFilter(in: "pdfs from the past week", now: now)?.range == lastWeek.range,
                    "past week did not match last week")

        let today = try requireValue(FileSearch.dateFilter(in: "today", now: now))
        try require(today.range.start == date("2026-11-25 00:00") && today.range.end == now, "today range was wrong")
        let yesterday = try requireValue(FileSearch.dateFilter(in: "pdfs yesterday", now: now))
        try require(yesterday.range == DateInterval(start: date("2026-11-24 00:00"), end: date("2026-11-25 00:00")),
                    "yesterday range was wrong")
        let lastMonth = try requireValue(FileSearch.dateFilter(in: "videos from last month", now: now))
        try require(lastMonth.range.start == date("2026-10-01 00:00"), "last month did not start on 1 October")
        let thisMonth = try requireValue(FileSearch.dateFilter(in: "this month", now: now))
        try require(thisMonth.range.start == date("2026-11-01 00:00"), "this month did not start on 1 November")
        try require(FileSearch.dateFilter(in: "holiday photos", now: now) == nil, "a search without a date got one")

        try require(FileSearch.removingDate(from: "screenshots from last week") == "screenshots",
                    "date phrase was not removed")
        try require(FileSearch.removingDate(from: "Large videos This Month") == "Large videos",
                    "date phrase removal was case sensitive")

        // The search itself: Monday's screenshot (this week) and last Thursday's
        // match; one from three weeks ago and a script named "screenshot" don't.
        let files = [
            screenshot("Screenshot 2026-11-23 at 10.00.00.png", "2026-11-23 10:00"),
            screenshot("Screenshot 2026-11-19 at 18.30.00.png", "2026-11-19 18:30"),
            screenshot("Screenshot 2026-11-04 at 09.00.00.png", "2026-11-04 09:00"),
            screenshot("take-screenshot.js", "2026-11-24 12:00"),
        ]
        let found = FileSearch.filter(files, query: "screenshots from last week", category: "Home", folder: nil, now: now)
        try require(found.map(\.name) == ["Screenshot 2026-11-23 at 10.00.00.png", "Screenshot 2026-11-19 at 18.30.00.png"],
                    "screenshots from last week found \(found.map(\.name))")
        let all = FileSearch.filter(files, query: FileSearch.removingDate(from: "screenshots from last week"),
                                    category: "Home", folder: nil, now: now)
        try require(all.count == 3, "screenshots on all dates found \(all.map(\.name))")
        let none = FileSearch.filter(files, query: "screenshots today", category: "Home", folder: nil, now: now)
        try require(none.isEmpty, "screenshots today should be empty, found \(none.map(\.name))")
    }

    static func requireValue<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure(description: "expected a value") }
        return value
    }
}
