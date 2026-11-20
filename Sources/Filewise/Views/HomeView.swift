import FilewiseCore
import SwiftUI

struct HomeView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var navigation: FilewiseNavigation
    let recentFiles: [FileItem]
    let onPreview: (FileItem) -> Void
    let onTrash: ([FileItem]) -> Void

    private let grid = [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: Theme.Spacing.l)]
    private let cleanupCategories = ["Duplicates", "Forgotten Downloads", "Old Screenshots", "Large Files"]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if library.folder != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(greeting).font(Theme.pageTitle).accessibilityAddTraits(.isHeader)
                    Text("\(Theme.count(library.files.count, "file")) · \(Theme.bytes(library.summary(for: "Home").bytes)) in \(library.folder?.lastPathComponent ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
            if library.folder == nil {
                WelcomeView(library: library)
            } else if !library.scanning && library.files.isEmpty && library.scanNotice != nil {
                ScanNoticeView(library: library)
            } else {
                if !library.scanning && library.scanNotice != nil {
                    ScanNoticeView(library: library)
                }
                section("Library") {
                    LazyVGrid(columns: grid, spacing: Theme.Spacing.l) {
                        ForEach(Theme.libraryCategories, id: \.self, content: libraryCard)
                    }
                }
                recentMedia
                section("Clean Up", seeAll: "Clean Up") {
                    // One row of four when it fits, otherwise a balanced 2×2 grid.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.l) {
                            ForEach(cleanupCategories, id: \.self) { cleanupCard($0).frame(minWidth: 130) }
                        }
                        Grid(horizontalSpacing: Theme.Spacing.l, verticalSpacing: Theme.Spacing.l) {
                            GridRow { cleanupCard(cleanupCategories[0]); cleanupCard(cleanupCategories[1]) }
                            GridRow { cleanupCard(cleanupCategories[2]); cleanupCard(cleanupCategories[3]) }
                        }
                    }
                }
                downloadedFrom
                section("Recent Files", seeAll: "Recents") {
                    if recentFiles.isEmpty {
                        Text(library.scanning ? "Indexing your files…" : "No files found")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(recentFiles) { item in
                                recentRow(item)
                                if item.id != recentFiles.last?.id { Divider().padding(.leading, 56) }
                            }
                        }
                        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                        // Long file names must not widen the page: the split view
                        // would shrink the sidebar and inspector to make room.
                        .frame(minWidth: 0, idealWidth: 300, maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func section<Content: View>(_ title: String, seeAll category: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Theme.sectionTitle).accessibilityAddTraits(.isHeader)
                Spacer()
                if let category {
                    Button("See All") { library.category = category }
                        .buttonStyle(.link)
                        .accessibilityLabel("See all \(title.lowercased())")
                }
            }
            content()
        }
    }

    private func libraryCard(_ title: String) -> some View {
        LibraryCard(title: title,
                    summary: library.summary(for: title),
                    totalBytes: library.summary(for: "Home").bytes,
                    previews: Array(library.files.lazy.filter { $0.libraryCategory == title }.prefix(3))) {
            library.category = title
        }
    }

    private func cleanupCard(_ category: String) -> some View {
        CleanupCard(category: category, summary: library.summary(for: category)) {
            library.category = category
        }
    }

    private var downloadedFrom: some View {
        section("Downloaded From", seeAll: library.downloadSources.isEmpty ? nil : "Downloaded From") {
            if library.downloadSources.isEmpty {
                Label("No download sources found in this folder.", systemImage: "network")
                    .foregroundStyle(.secondary)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(library.topDownloadSources.prefix(8), id: \.key) { source, summary in
                            sourceCard(source, summary)
                        }
                    }
                }
            }
        }
    }

    private func sourceCard(_ source: String, _ summary: LibrarySummary) -> some View {
        let color = Theme.originColor(source)
        return Button { library.category = "Origin: \(source)" } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: Theme.originIcon(source))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(Theme.tint(color), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(source).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(Theme.count(summary.count, "file")) · \(Theme.bytes(summary.bytes))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
            .frame(minWidth: 170, alignment: .leading)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Downloaded from \(source), \(Theme.count(summary.count, "file"))")
    }

    /// The newest photos and videos as a strip of previews.
    @ViewBuilder private var recentMedia: some View {
        let media = Array(library.files.lazy.filter { $0.isImage || $0.libraryCategory == "Videos" }.prefix(12))
        if !media.isEmpty {
            section("Recent Photos & Videos", seeAll: "Images") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(media) { item in
                            MediaTile(item: item, side: 112, isSelected: library.selectedIDs.contains(item.id),
                                      onPlay: {
                                          navigation.showInspector = true
                                          library.play(item)
                                      })
                                .onTapGesture(count: 2) { FileActions.open([item]) }
                                .onTapGesture { library.selectedIDs = [item.id] }
                                .contextMenu { FileMenuItems(items: [item], onPreview: onPreview, onTrash: onTrash) }
                                .accessibilityAction { library.selectedIDs = [item.id] }
                                .fileAccessibilityActions(item, onPreview: onPreview, onTrash: onTrash)
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ item: FileItem) -> some View {
        let isSelected = library.selectedIDs.contains(item.id)
        return HStack(spacing: Theme.Spacing.m) {
            FileNameCell(item: item, location: library.displayLocation(for: item))
            Spacer()
            ReasonTags(reasons: item.cleanupReasons)
            Text(item.displaySize).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(item.modified.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.m).padding(.vertical, Theme.Spacing.s)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
        .id(item.id)
        .onTapGesture(count: 2) { FileActions.open([item]) }
        .onTapGesture { library.selectedIDs = [item.id] }
        .contextMenu { FileMenuItems(items: [item], onPreview: onPreview, onTrash: onTrash) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { library.selectedIDs = [item.id] }
        .fileAccessibilityActions(item, onPreview: onPreview, onTrash: onTrash)
    }
}

extension Library {
    /// A problem with the latest scan worth explaining, if any.
    var scanNotice: (title: String, message: String, icon: String)? {
        if indexUnavailable {
            return ("Index unavailable",
                    "Filewise could not save the index. Use Rebuild Index in the sidebar, or open its folder to keep a copy for recovery.",
                    "exclamationmark.triangle")
        }
        if status == "Scan cancelled" {
            return ("Scan cancelled",
                    files.isEmpty ? "This folder has not been indexed yet. Restart the scan to see its files."
                                  : "The scan stopped. Previous results are still shown.",
                    "pause.circle")
        }
        if status.contains("unavailable") {
            return ("Folder unavailable",
                    files.isEmpty ? "Filewise could not read this folder. Check its permissions, reconnect its drive, or choose another folder."
                                  : "Filewise could not read this folder or all of its files. Previous results are still shown.",
                    "folder.badge.questionmark")
        }
        return nil
    }
}

struct ScanNoticeView: View {
    @ObservedObject var library: Library

    var body: some View {
        if let notice = library.scanNotice {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: notice.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(notice.title).font(.headline)
                    Text(notice.message).foregroundStyle(.secondary)
                    HStack(spacing: Theme.Spacing.s) {
                        if let folder = library.folder {
                            Button("Try Again") { library.scan(folder) }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Choose Folder…") { library.chooseFolder() }
                    }
                    .padding(.top, Theme.Spacing.xxs)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.tint(.orange), in: RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
    }
}

/// A Library category card: a colored badge, a fanned stack of the newest
/// files' previews, and the category's count, size, and share of the folder.
private struct LibraryCard: View {
    let title: String
    let summary: LibrarySummary
    let totalBytes: Int64
    let previews: [FileItem]
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var color: Color { Theme.color(for: title) }
    private var isEmpty: Bool { summary.count == 0 }
    private var share: Double { totalBytes > 0 ? Double(summary.bytes) / Double(totalBytes) : 0 }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: Theme.icon(for: title))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(colors: [color.opacity(0.85), color],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: color.opacity(0.35), radius: 4, y: 2)
                    Spacer()
                    previewStack
                }
                Spacer(minLength: Theme.Spacing.l)
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(isEmpty ? "No files" : "\(Theme.count(summary.count, "item")) · \(Theme.bytes(summary.bytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                shareBar.padding(.top, Theme.Spacing.s)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .strokeBorder(color.opacity(isHovering ? 0.45 : 0.18), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
            .shadow(color: .black.opacity(isHovering ? 0.12 : 0.04), radius: isHovering ? 10 : 3, y: isHovering ? 4 : 1)
            .scaleEffect(isHovering ? 1.015 : 1)
            .opacity(isEmpty ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .accessibilityLabel("\(title), \(Theme.count(summary.count, "item")), \(Theme.bytes(summary.bytes))")
        .accessibilityHint("Shows files in this category")
    }

    private var background: some View {
        LinearGradient(colors: [color.opacity(colorScheme == .dark ? 0.28 : 0.16),
                                color.opacity(colorScheme == .dark ? 0.10 : 0.05)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Up to three of the newest files, fanned like a small stack of cards.
    private var previewStack: some View {
        ZStack {
            ForEach(Array(previews.enumerated().reversed()), id: \.element.id) { index, item in
                FileThumbnail(item: item, size: 40, cornerRadius: 7, showsPlayBadge: false)
                    .padding(2)
                    .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: CGFloat(index - 1) * -14)
            }
        }
        .frame(width: 76, height: 48, alignment: .trailing)
        .accessibilityHidden(true)
    }

    /// The category's share of the folder's total size.
    private var shareBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: share > 0 ? max(4, geometry.size.width * share) : 0)
            }
        }
        .frame(height: 4)
        .help(share > 0 ? "\(Int((share * 100).rounded()))% of this folder’s size" : "")
        .accessibilityHidden(true)
    }
}

/// A cleanup suggestion card in the same style as the Library cards, led by
/// the size that could be reviewed.
private struct CleanupCard: View {
    let category: String
    let summary: LibrarySummary
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var color: Color { Theme.color(for: category) }
    private var isEmpty: Bool { summary.count == 0 }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: Theme.icon(for: category))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(colors: [color.opacity(0.85), color],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: color.opacity(0.35), radius: 3, y: 1.5)
                    Spacer()
                    if !isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: Theme.Spacing.m)
                Text(Theme.title(for: category))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(isEmpty ? "All clear" : Theme.bytes(summary.bytes))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isEmpty ? "Nothing to review" : Theme.count(summary.count, "file") + " to review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
            .background(
                LinearGradient(colors: [color.opacity(colorScheme == .dark ? 0.22 : 0.12),
                                        color.opacity(colorScheme == .dark ? 0.07 : 0.03)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .strokeBorder(color.opacity(isHovering ? 0.45 : 0.15), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
            .shadow(color: .black.opacity(isHovering ? 0.12 : 0.04), radius: isHovering ? 10 : 3, y: isHovering ? 4 : 1)
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .accessibilityLabel("\(Theme.title(for: category)), \(Theme.count(summary.count, "file")), \(Theme.bytes(summary.bytes))")
        .accessibilityHint("Review cleanup candidates")
    }
}
