import FilewiseCore
import Foundation

@main
struct LicenseHarness {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition {
                fputs("FAIL: \(message)\n", stderr)
                failures += 1
            }
        }
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func status(after elapsed: TimeInterval, unlocked: Bool = false) -> LicenseStatus {
            License.status(trialStart: start, unlocked: unlocked, now: start.addingTimeInterval(elapsed))
        }

        check(status(after: 0) == .trial(daysLeft: 7), "a new download has 7 days")
        check(status(after: 60) == .trial(daysLeft: 7), "partial days count up")
        check(status(after: day) == .trial(daysLeft: 6), "one day later leaves 6")
        check(status(after: 6 * day + 1) == .trial(daysLeft: 1), "the last day shows 1")
        check(status(after: 7 * day) == .expired, "the trial ends after exactly 7 days")
        check(status(after: 30 * day) == .expired, "it stays expired")
        check(status(after: -10 * day) == .trial(daysLeft: 7), "a future start never gives more than 7 days")
        check(status(after: 30 * day, unlocked: true) == .unlocked, "the unlock outlasts the trial")
        check(status(after: 0, unlocked: true) == .unlocked, "the unlock applies during the trial")
        check(License.status(trialStart: nil, unlocked: false, checked: false) == .checking,
              "before StoreKit answers it is checking")
        check(License.status(trialStart: nil, unlocked: false) == .notStarted, "an unstarted trial is offered")
        check(License.status(trialStart: nil, unlocked: true) == .unlocked, "buying without a trial unlocks")

        check(LicenseStatus.trial(daysLeft: 1).allowsCleanup, "cleanup is allowed in the trial")
        check(LicenseStatus.unlocked.allowsCleanup, "cleanup is allowed when unlocked")
        check(LicenseStatus.checking.allowsCleanup, "cleanup is allowed while checking")
        check(!LicenseStatus.expired.allowsCleanup, "cleanup is locked after the trial")
        check(!LicenseStatus.notStarted.allowsCleanup, "cleanup waits for the trial to start")

        if failures > 0 { exit(1) }
        print("PASS: trial start, length, day counting, expiry, unlock, and cleanup gating")
    }
}
