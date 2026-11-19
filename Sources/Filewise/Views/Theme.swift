import AppKit
import FilewiseCore
import SwiftUI

/// Shared design tokens. Colors are semantic or tinted so every surface reads
/// correctly in both light and dark appearances.
enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let page: CGFloat = 28
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
    }

    static let pageTitle = Font.system(size: 26, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)

    /// Neutral fill for grouped content; adapts to the appearance.
    static let subtleFill = Color.primary.opacity(0.05)
    static let hairline = Color.primary.opacity(0.1)

    static func tint(_ color: Color) -> Color { color.opacity(0.14) }

    static let libraryCategories = ["Images", "Videos", "Music", "Documents", "Archives", "Apps"]

    static func icon(for category: String) -> String {
        switch category {
        case "Home": "house"
        case "Recents": "clock"
        case "Images": "photo"
        case "Videos": "play.rectangle"
        case "Music": "music.note"
        case "Documents": "doc.text"
        case "Archives": "archivebox"
        case "Apps": "square.grid.2x2"
        case "Large Files": "externaldrive"
        case "Screenshots", "Old Screenshots": "camera.viewfinder"
        case "Duplicates": "square.on.square"
        case "Clean Up": "sparkles"
        case "Downloads", "Forgotten Downloads": "arrow.down.circle"
        case "Downloaded From": "network"
        default: "doc"
        }
    }

    static func color(for category: String) -> Color {
        switch category {
        case "Images": .indigo
        case "Videos": .blue
        case "Music": .orange
        case "Documents": .teal
        case "Archives": .brown
        case "Apps": .pink
        case "Duplicates": .red
        case "Forgotten Downloads": .blue
        case "Old Screenshots": .purple
        case "Large Files": .green
        default: .accentColor
        }
    }

    static func color(for reason: CleanupReason) -> Color {
        switch reason {
        case .duplicate: .red
        case .large: .green
        case .oldScreenshot: .purple
        case .forgottenDownload: .blue
        }
    }

    /// Title shown for a category, including download-origin filters.
    static func title(for category: String) -> String {
        if category.hasPrefix("Origin: ") { return "From " + category.dropFirst("Origin: ".count) }
        switch category {
        case "Clean Up": return "Clean Up Suggestions"
        case "Forgotten Downloads": return "Old Downloads"
        default: return category
        }
    }

    static func originIcon(_ source: String) -> String {
        switch source.lowercased() {
        case "canva": "paintbrush.pointed"
        case "chatgpt": "bubble.left.and.text.bubble.right"
        case "x", "twitter": "message"
        case "github", "gitlab": "chevron.left.forwardslash.chevron.right"
        case "pinterest": "pin"
        case "figma": "square.on.circle"
        case "google", "google chrome": "globe"
        case "safari": "safari"
        case "slack": "number"
        case "discord": "bubble.left"
        case "telegram": "paperplane"
        case "youtube": "play.rectangle"
        default: "arrow.down.circle"
        }
    }

    static func originColor(_ source: String) -> Color {
        switch source.lowercased() {
        case "canva": .teal
        case "chatgpt": .green
        case "x", "twitter": .primary
        case "github": .purple
        case "pinterest", "youtube": .red
        case "figma": .orange
        case "slack": .indigo
        default: .blue
        }
    }

    // Formatters are not thread-safe; only views use this one.
    @MainActor private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    @MainActor static func bytes(_ count: Int64) -> String { byteFormatter.string(fromByteCount: count) }

    /// "1 file", "3 files"
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value.formatted()) \(value == 1 ? singular : plural ?? singular + "s")"
    }
}

enum FileActions {
    static func open(_ items: [FileItem]) {
        for item in items { NSWorkspace.shared.open(item.url) }
    }

    static func reveal(_ items: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }
}

/// Context-menu items shared by every file list.
struct FileMenuItems: View {
    let items: [FileItem]
    let onPreview: (FileItem) -> Void
    let onTrash: ([FileItem]) -> Void

    var body: some View {
        if items.count == 1, let item = items.first {
            Button("Quick Look") { onPreview(item) }
        }
        Button(items.count == 1 ? "Open" : "Open \(items.count) Files") { FileActions.open(items) }
        Button("Show in Finder") { FileActions.reveal(items) }
        Divider()
        Button(items.count == 1 ? "Move to Trash…" : "Move \(items.count) Files to Trash…", role: .destructive) {
            onTrash(items)
        }
    }
}

/// Compact colored labels explaining why a file is a cleanup candidate.
struct ReasonTags: View {
    let reasons: [CleanupReason]

    var body: some View {
        // Show every tag when it fits; otherwise the first tag and a count.
        ViewThatFits(in: .horizontal) {
            tags(reasons, hidden: 0)
            tags(Array(reasons.prefix(1)), hidden: reasons.count - 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reasons.map(\.label).joined(separator: ", "))
    }

    private func tags(_ shown: [CleanupReason], hidden: Int) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(shown, id: \.self) { reason in
                Text(reason.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.color(for: reason))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.tint(Theme.color(for: reason)), in: Capsule())
                    .fixedSize()
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .help(reasons.map { "\($0.label): \($0.explanation)" }.joined(separator: "\n"))
    }
}

/// File icon, name, and its location within the selected folder.
struct FileNameCell: View {
    let item: FileItem
    let location: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(nsImage: IconCache.shared.icon(for: item))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 2)
        .help(item.url.path)
    }
}
