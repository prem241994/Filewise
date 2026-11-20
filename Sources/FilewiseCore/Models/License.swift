import Foundation

/// Whether cleanup actions are available: during the free trial and after
/// the one-time unlock. Searching, browsing, suggestions, and Undo are
/// always free.
public enum LicenseStatus: Equatable, Sendable {
    /// StoreKit has not answered yet. Cleanup is allowed so a slow App Store
    /// never blocks someone who has paid.
    case checking
    /// The free trial is offered but not started. App Review requires the
    /// trial's length, what it gates, and the price to be shown before it starts.
    case notStarted
    case trial(daysLeft: Int)
    case expired
    case unlocked

    public var allowsCleanup: Bool {
        switch self {
        case .checking, .trial, .unlocked: true
        case .notStarted, .expired: false
        }
    }
}

public enum License {
    public static let trialDays = 7
    /// The non-consumable in-app purchase configured in App Store Connect.
    public static let unlockProductID = "app.filewise.desktop.unlock"
    /// The free ($0) non-consumable named "7-day Trial" that starts the trial,
    /// as App Review Guideline 3.1.1 describes.
    public static let trialProductID = "app.filewise.desktop.trial"

    /// The status for a trial that began at `trialStart` (when the user
    /// started it), or nil if they have not. `checked` is false until StoreKit
    /// has answered. Days left counts partial days up, so a new trial shows 7
    /// and the last day shows 1.
    public static func status(trialStart: Date?, unlocked: Bool, checked: Bool = true,
                              now: Date = Date()) -> LicenseStatus {
        if unlocked { return .unlocked }
        guard let trialStart else { return checked ? .notStarted : .checking }
        let end = trialStart.addingTimeInterval(TimeInterval(trialDays) * 86_400)
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }
        // A start date in the future (clock changes) still shows a full trial, not more.
        return .trial(daysLeft: min(trialDays, Int((remaining / 86_400).rounded(.up))))
    }
}
