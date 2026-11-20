import AppKit
import FilewiseCore
import StoreKit

/// A request to show the unlock sheet, naming what the user tried to clean up.
struct PaywallRequest: Identifiable {
    let id = UUID()
    let bytes: Int64
    let count: Int
}

/// The free trial and the one-time unlock, through StoreKit 2 with no server.
/// The trial starts at the App Store's original download date, so reinstalling
/// does not restart it. Cleanup actions ask `requireUnlock` first.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var status: LicenseStatus = .checking
    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: String?
    @Published var paywall: PaywallRequest?

    private var trialStart: Date?
    private var unlocked = false
    private var updates: Task<Void, Never>?
    private static let firstLaunchKey = "filewise.firstLaunchDate"

    #if FILEWISE_LICENSE_TESTING
    /// FILEWISE_LICENSE=trial:<days>|expired|unlocked replaces StoreKit in
    /// development builds (built with FILEWISE_LICENSE_TESTING=1).
    private let override = ProcessInfo.processInfo.environment["FILEWISE_LICENSE"]
    #endif

    init() {
        #if FILEWISE_SNAPSHOT
        SnapshotHook.store = self
        #endif
        #if FILEWISE_LICENSE_TESTING
        if let override {
            applyOverride(override)
            return
        }
        #endif
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        Task { await refresh() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            // The trial can end while the app stays open.
            MainActor.assumeIsolated { self?.updateStatus() }
        }
    }

    var priceText: String {
        #if FILEWISE_LICENSE_TESTING
        if override != nil { return "$4.99" }
        #endif
        return product?.displayPrice ?? ""
    }

    /// Runs `action` when cleanup is allowed; otherwise shows the unlock sheet.
    func requireUnlock(bytes: Int64, count: Int, _ action: () -> Void) {
        updateStatus()
        if status.allowsCleanup {
            action()
        } else {
            purchaseError = nil
            paywall = PaywallRequest(bytes: bytes, count: count)
        }
    }

    /// Shows the unlock sheet on the main window, bringing it forward (for
    /// the menu command and Settings).
    func showUnlock() {
        purchaseError = nil
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        paywall = PaywallRequest(bytes: 0, count: 0)
    }

    func refresh() async {
        trialStart = await Self.originalDownloadDate() ?? Self.firstLaunchDate()
        unlocked = await Self.ownsUnlock()
        updateStatus()
        if product == nil {
            product = try? await Product.products(for: [License.unlockProductID]).first
        }
    }

    func purchase() async {
        #if FILEWISE_LICENSE_TESTING
        if override != nil {
            unlocked = true
            updateStatus()
            paywall = nil
            return
        }
        #endif
        purchaseError = nil
        if product == nil { await refresh() }
        guard let product else {
            purchaseError = "The App Store can’t be reached right now. Check your internet connection and try again."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                unlocked = true
                updateStatus()
                paywall = nil
            case .success(.unverified):
                purchaseError = "The App Store couldn’t verify this purchase. Try Restore Purchase."
            case .pending:
                purchaseError = "Your purchase is waiting for approval. Filewise unlocks as soon as it’s approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "The purchase didn’t go through: \(error.localizedDescription)"
        }
    }

    func restore() async {
        #if FILEWISE_LICENSE_TESTING
        if override != nil { return }
        #endif
        purchaseError = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            purchaseError = "Couldn’t restore: \(error.localizedDescription)"
            return
        }
        await refresh()
        if unlocked {
            paywall = nil
        } else {
            purchaseError = "No Filewise purchase was found for this Apple Account."
        }
    }

    private func updateStatus() {
        #if FILEWISE_LICENSE_TESTING
        if override != nil, !unlocked { return }
        #endif
        status = License.status(trialStart: trialStart, unlocked: unlocked)
    }

    // MARK: - StoreKit

    /// When this Apple Account first downloaded Filewise. Nil outside an App
    /// Store install (development builds).
    private static func originalDownloadDate() async -> Date? {
        guard let result = try? await AppTransaction.shared, case .verified(let app) = result else { return nil }
        return app.originalPurchaseDate
    }

    private static func ownsUnlock() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == License.unlockProductID,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// The trial start when the App Store has no record, such as a build run
    /// outside the App Store. Saved on first use.
    private static func firstLaunchDate() -> Date {
        if let date = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date { return date }
        let now = Date()
        UserDefaults.standard.set(now, forKey: firstLaunchKey)
        return now
    }

    #if FILEWISE_LICENSE_TESTING
    private func applyOverride(_ value: String) {
        if value == "unlocked" {
            unlocked = true
            status = .unlocked
        } else if value == "expired" {
            status = .expired
        } else if value.hasPrefix("trial:"), let days = Int(value.dropFirst(6)) {
            status = .trial(daysLeft: days)
        }
    }
    #endif
}
