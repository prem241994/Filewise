import SwiftUI

struct HomeView: View {
    @ObservedObject var library: Library
    let recentFiles: [FileItem]
    let onPreview: (FileItem) -> Void
    let onTrash: ([FileItem]) -> Void

    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 280), spacing: Theme.Spacing.l)]
    private let cleanupCategories = ["Duplicates", "Forgotten Downloads", "Old Screenshots", "Large Files"]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(greeting).font(Theme.pageTitle)
                if library.folder != nil {
                    Text("\(Theme.count(library.files.count, "file")) · \(Theme.bytes(library.summary(for: "Home").bytes)) in \(library.folder?.lastPathComponent ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
            if library.folder == nil {
                welcome
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
                                if item.id != recentFiles.last?.id { Divider().padding(.leading, 48) }
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

    private var welcome: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "folder.badge.plus").font(.system(size: 36)).foregroundStyle(.tint)
            Text("Your files, in one place").font(.title3.weight(.semibold))
            Text("Choose a folder to explore its files and cleanup suggestions. Filewise keeps everything on this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Folder…") { library.chooseFolder() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Text("You can also drop a folder onto this window.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Theme.tint(.accentColor), in: RoundedRectangle(cornerRadius: Theme.Radius.l))
    }

    private func section<Content: View>(_ title: String, seeAll category: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Theme.sectionTitle)
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
        let summary = library.summary(for: title)
        let color = Theme.color(for: title)
        return Button { library.category = title } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: Theme.icon(for: title))
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Spacer(minLength: 22)
                Text(title).font(.system(size: 15, weight: .semibold))
                Text("\(Theme.count(summary.count, "item")) · \(Theme.bytes(summary.bytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Theme.tint(color), in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(Theme.count(summary.count, "item")), \(Theme.bytes(summary.bytes))")
        .accessibilityHint("Shows files in this category")
    }

    private func cleanupCard(_ category: String) -> some View {
        let summary = library.summary(for: category)
        let color = Theme.color(for: category)
        return Button { library.category = category } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: Theme.icon(for: category))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(Theme.tint(color), in: Circle())
                Spacer(minLength: 16)
                Text(Theme.title(for: category)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(Theme.bytes(summary.bytes))
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(Theme.count(summary.count, "file")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Theme.title(for: category)), \(Theme.count(summary.count, "file")), \(Theme.bytes(summary.bytes))")
        .accessibilityHint("Review cleanup candidates")
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
