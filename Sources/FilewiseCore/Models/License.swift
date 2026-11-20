import Foundation

/// Whether cleanup actions are available: during the free trial and after
/// the one-time unlock. Searching, browsing, suggestions, and Undo are
/// always free.
public enum LicenseStatus: Equatable, Sendable {
    /// StoreKit has not answered yet. Cleanup is allowed so a slow App Store
    /// never blocks someone who has paid.
    case checking
    case trial(daysLeft: Int)
    case expired
    case unlocked

    public var allowsCleanup: Bool { self != .expired }
}

public enum License {
    public static let trialDays = 7
    /// The non-consumable in-app purchase configured in App Store Connect.
    public static let unlockProductID = "app.filewise.desktop.unlock"

    /// The status for a trial that began at `trialStart` (the App Store's
    /// original download date). Days left counts partial days up, so a new
    /// download shows 7 and the last day shows 1.
    public static func status(trialStart: Date?, unlocked: Bool, now: Date = Date()) -> LicenseStatus {
        if unlocked { return .unlocked }
        guard let trialStart else { return .checking }
        let end = trialStart.addingTimeInterval(TimeInterval(trialDays) * 86_400)
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }
        // A start date in the future (clock changes) still shows a full trial, not more.
        return .trial(daysLeft: min(trialDays, Int((remaining / 86_400).rounded(.up))))
    }
}
