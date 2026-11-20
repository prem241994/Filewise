import AppKit
import FilewiseCore
import StoreKit

/// A request to show the unlock sheet, naming what the user tried to clean up.
struct PaywallRequest: Identifiable {
    let id = UUID()
    let bytes: Int64
    let count: Int
    /// Shown by itself when the trial has ended, rather than from an action.
    var trialEnded = false
}

/// The free trial and the one-time unlock, through StoreKit 2 with no server.
///
/// As App Review Guideline 3.1.1 describes, the trial is a free non-consumable
/// ("7-day Trial") that the user starts after the app has shown its length,
/// what it gates, and the price. Its purchase date starts the 7 days, and it
/// stays in the user's purchases, so reinstalling does not restart it. Outside
/// an App Store install (development builds) the trial is kept locally.
/// Cleanup actions ask `requireUnlock` first.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var status: LicenseStatus = .checking
    @Published private(set) var product: Product?
    @Published private(set) var trialProduct: Product?
    @Published private(set) var isPurchasing = false
    @Published var purchaseError: String?
    @Published var paywall: PaywallRequest?

    private var trialStart: Date?
    private var unlocked = false
    private var checked = false
    private var updates: Task<Void, Never>?
    private static let localTrialKey = "filewise.localTrialStart"

    #if FILEWISE_LICENSE_TESTING
    /// FILEWISE_LICENSE=new|trial:<days>|expired|unlocked replaces StoreKit in
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

    /// The unlock price in the user's currency, or empty when the App Store
    /// has not answered.
    var priceText: String {
        #if FILEWISE_LICENSE_TESTING
        if override != nil { return "$4.99" }
        #endif
        return product?.displayPrice ?? ""
    }

    /// The disclosure App Review requires before the trial starts.
    var trialTerms: String {
        let price = priceText.isEmpty ? "a one-time purchase" : "a one-time \(priceText) purchase"
        return "Try every feature free for \(License.trialDays) days. After that, moving files to the Trash and selecting extra copies need \(price). Searching, browsing, suggestions, and Undo stay free."
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
        let owned = await Self.ownedProducts()
        unlocked = owned[License.unlockProductID] != nil
        trialStart = owned[License.trialProductID]
            ?? UserDefaults.standard.object(forKey: Self.localTrialKey) as? Date
        checked = true
        updateStatus()
        if product == nil || trialProduct == nil,
           let products = try? await Product.products(for: [License.unlockProductID, License.trialProductID]) {
            product = products.first { $0.id == License.unlockProductID }
            trialProduct = products.first { $0.id == License.trialProductID }
        }
    }

    /// Starts the 7-day trial through the free "7-day Trial" purchase.
    func startTrial() async {
        #if FILEWISE_LICENSE_TESTING
        if override != nil {
            status = .trial(daysLeft: License.trialDays)
            paywall = nil
            return
        }
        #endif
        purchaseError = nil
        if trialProduct == nil { await refresh() }
        guard let trialProduct else {
            // Not an App Store install, or the App Store is unreachable: keep
            // the trial locally so the app still works.
            UserDefaults.standard.set(Date(), forKey: Self.localTrialKey)
            trialStart = Date()
            updateStatus()
            paywall = nil
            return
        }
        if let transaction = await buy(trialProduct) {
            trialStart = transaction.purchaseDate
            updateStatus()
            paywall = nil
        }
    }

    func purchase() async {
        #if FILEWISE_LICENSE_TESTING
        if override != nil {
            unlocked = true
            status = .unlocked
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
        if await buy(product) != nil {
            unlocked = true
            updateStatus()
            paywall = nil
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
        if override != nil { return }
        #endif
        status = License.status(trialStart: trialStart, unlocked: unlocked, checked: checked)
    }

    // MARK: - StoreKit

    /// Purchases `product`, returning the verified transaction, or nil after
    /// showing why not (or if the user cancelled).
    private func buy(_ product: Product) async -> Transaction? {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                return transaction
            case .success(.unverified):
                purchaseError = "The App Store couldn’t verify this purchase. Try Restore Purchase."
            case .pending:
                purchaseError = "Your purchase is waiting for approval. Filewise updates as soon as it’s approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "The purchase didn’t go through: \(error.localizedDescription)"
        }
        return nil
    }

    /// The purchase date of each Filewise product this Apple Account owns.
    private static func ownedProducts() async -> [String: Date] {
        var owned: [String: Date] = [:]
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                owned[transaction.productID] = transaction.purchaseDate
            }
        }
        return owned
    }

    #if FILEWISE_LICENSE_TESTING
    private func applyOverride(_ value: String) {
        if value == "unlocked" {
            unlocked = true
            status = .unlocked
        } else if value == "expired" {
            status = .expired
        } else if value == "new" {
            status = .notStarted
        } else if value.hasPrefix("trial:"), let days = Int(value.dropFirst(6)) {
            status = .trial(daysLeft: days)
        }
    }
    #endif
}
