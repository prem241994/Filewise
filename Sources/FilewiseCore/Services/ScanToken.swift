import os

/// A cancellation flag shared between the main actor and background work.
public final class ScanToken: Sendable {
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public var isCancelled: Bool { cancelled.withLock { $0 } }

    public func cancel() { cancelled.withLock { $0 = true } }
}
