import FilewiseCore
import Foundation

/// Preferences shown in the Settings window. Saving one updates
/// `CleanupSettings.current`, which the scanner and file rules read.
@MainActor
final class AppSettings: ObservableObject {
    static let largeFileChoices: [Int64] = [50, 100, 250, 500, 1_000].map { $0 * 1_000_000 }
    static let oldAfterChoices = [7, 14, 30, 60, 90, 180]

    @Published var largeFileBytes: Int64 { didSet { save() } }
    @Published var oldAfterDays: Int { didSet { save() } }
    @Published private(set) var ignoredFolders: [String] { didSet { save() } }

    private let defaults: UserDefaults
    private static let largeKey = "filewise.largeFileBytes"
    private static let oldKey = "filewise.oldAfterDays"
    private static let ignoredKey = "filewise.ignoredFolders"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let large = Int64(defaults.integer(forKey: Self.largeKey))
        let old = defaults.integer(forKey: Self.oldKey)
        largeFileBytes = Self.largeFileChoices.contains(large) ? large : CleanupSettings.defaultLargeFileBytes
        oldAfterDays = Self.oldAfterChoices.contains(old) ? old : CleanupSettings.defaultOldAfterDays
        ignoredFolders = defaults.stringArray(forKey: Self.ignoredKey) ?? []
        apply()
    }

    var isDefault: Bool {
        largeFileBytes == CleanupSettings.defaultLargeFileBytes
            && oldAfterDays == CleanupSettings.defaultOldAfterDays && ignoredFolders.isEmpty
    }

    func ignore(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard !ignoredFolders.contains(path) else { return }
        ignoredFolders = (ignoredFolders + [path]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func stopIgnoring(_ path: String) {
        ignoredFolders.removeAll { $0 == path }
    }

    func resetToDefaults() {
        largeFileBytes = CleanupSettings.defaultLargeFileBytes
        oldAfterDays = CleanupSettings.defaultOldAfterDays
        ignoredFolders = []
    }

    private func save() {
        defaults.set(largeFileBytes, forKey: Self.largeKey)
        defaults.set(oldAfterDays, forKey: Self.oldKey)
        defaults.set(ignoredFolders, forKey: Self.ignoredKey)
        apply()
    }

    private func apply() {
        CleanupSettings.current = CleanupSettings(largeFileBytes: largeFileBytes, oldAfterDays: oldAfterDays,
                                                  ignoredFolders: ignoredFolders)
    }
}
