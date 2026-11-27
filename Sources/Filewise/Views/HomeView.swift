import FilewiseCore
import SwiftUI

struct HomeView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var navigation: FilewiseNavigation
    let recentFiles: [FileItem]
    let onPreview: (FileItem) -> Void
    let onTrash: ([FileItem]) -> Void

    private let grid = [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: Theme.Spacing.l)]
    /// Cleanup cards grouped by how readily their files can usually go.
    private static func cleanupCategories(_ confidence: CleanupConfidence) -> [String] {
        switch confidence {
        case .usuallySafe: ["Duplicates", "Forgotten Downloads", "Old Screenshots"]
        case .yourCall: ["Large Files"]
        }
    }

    /// The folder whose Home has already played its entrance, so returning to
    /// Home from another page doesn't replay it.
    private static var introPlayedFor: String?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if library.folder != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(greeting).font(Theme.pageTitle).accessibilityAddTraits(.isHeader)
                    Text("\(Theme.count(library.files.count, "file")) · \(Theme.bytes(library.summary(for: "Home").bytes)) in \(library.folder?.lastPathComponent ?? "")")
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
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
                SpaceRingView(library: library).entrance(appeared, order: 0)
                section("Library") {
                    LazyVGrid(columns: grid, spacing: Theme.Spacing.l) {
                        ForEach(Theme.libraryCategories, id: \.self, content: libraryCard)
                    }
                }
                .entrance(appeared, order: 1)
                recentMedia.entrance(appeared, order: 2)
                section("Clean Up", seeAll: "Clean Up") {
                    // Both groups side by side when they fit, otherwise stacked.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                            cleanupGroup(.usuallySafe).layoutPriority(3)
                            cleanupGroup(.yourCall).frame(minWidth: 150, maxWidth: 260)
                        }
                        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                            cleanupGroup(.usuallySafe)
                            cleanupGroup(.yourCall).frame(maxWidth: 260)
                        }
                    }
                }
                .entrance(appeared, order: 3)
                downloadedFrom.entrance(appeared, order: 4)
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
                .entrance(appeared, order: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: playIntro)
        .onChange(of: library.folder) { _, _ in playIntro() }
    }

    /// Lets the sections rise in once per folder; afterwards (or with Reduce
    /// Motion) they show at once.
    private func playIntro() {
        let path = library.folder?.path
        if reduceMotion || path == nil || Self.introPlayedFor == path {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { appeared = true }
            return
        }
        Self.introPlayedFor = path
        appeared = false
        DispatchQueue.main.async { appeared = true }
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

    private func cleanupGroup(_ confidence: CleanupConfidence) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label(confidence.title, systemImage: confidence.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(confidence == .usuallySafe ? Color.green : Color.orange)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Theme.Spacing.l) {
                ForEach(Self.cleanupCategories(confidence), id: \.self) { cleanupCard($0).frame(minWidth: 130) }
            }
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

/// The tinted card both the Library and Clean Up cards use: a soft gradient
/// in the category color, a border, and a small lift on hover. Values are
/// typed explicitly so the views type-check quickly (Swift 6.1 timed out).
private struct TintedCard: ViewModifier {
    let color: Color
    let isHovering: Bool
    /// Gradient opacities (top, bottom) in light and dark appearance.
    let light: (top: Double, bottom: Double)
    let dark: (top: Double, bottom: Double)
    let restingBorder: Double
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tint = colorScheme == .dark ? dark : light
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
        let gradient = LinearGradient(colors: [color.opacity(tint.top), color.opacity(tint.bottom)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        let borderOpacity: Double = isHovering ? 0.45 : restingBorder
        let shadowOpacity: Double = isHovering ? 0.12 : 0.04
        let shadowRadius: CGFloat = isHovering ? 10 : 3
        let shadowY: CGFloat = isHovering ? 4 : 1
        let scale: CGFloat = isHovering ? 1.015 : 1
        return content
            .background(gradient)
            .overlay(shape.strokeBorder(color.opacity(borderOpacity), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            .scaleEffect(scale)
            .contentShape(shape)
    }
}

/// A rounded square badge with a white symbol on the category's gradient.
private struct CategoryBadge: View {
    let symbol: String
    let color: Color
    let side: CGFloat
    let symbolSize: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        let gradient = LinearGradient(colors: [color.opacity(0.85), color],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(gradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: color.opacity(0.35), radius: side / 9, y: side / 18)
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

    private var color: Color { Theme.color(for: title) }
    private var isEmpty: Bool { summary.count == 0 }
    private var share: Double { totalBytes > 0 ? Double(summary.bytes) / Double(totalBytes) : 0 }
    private var detail: String {
        isEmpty ? "No files" : "\(Theme.count(summary.count, "item")) · \(Theme.bytes(summary.bytes))"
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .modifier(TintedCard(color: color, isHovering: isHovering,
                                     light: (0.16, 0.05), dark: (0.28, 0.10), restingBorder: 0.18))
                .opacity(isEmpty ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .accessibilityLabel("\(title), \(Theme.count(summary.count, "item")), \(Theme.bytes(summary.bytes))")
        .accessibilityHint("Shows files in this category")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                CategoryBadge(symbol: Theme.icon(for: title), color: color, side: 36, symbolSize: 16, cornerRadius: 10)
                Spacer()
                previewStack
            }
            Spacer(minLength: Theme.Spacing.l)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail)
                .contentTransition(.numericText())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            shareBar.padding(.top, Theme.Spacing.s)
        }
    }

    /// Up to three of the newest files, fanned like a small stack of cards.
    private var previewStack: some View {
        ZStack {
            ForEach(Array(previews.enumerated().reversed()), id: \.element.id) { index, item in
                previewCard(item, position: index - 1)
            }
        }
        .frame(width: 76, height: 48, alignment: .trailing)
        .accessibilityHidden(true)
    }

    /// One card of the stack; `position` is -1, 0, or 1 from front to back.
    private func previewCard(_ item: FileItem, position: Int) -> some View {
        let angle: Double = Double(position) * 8
        let shift: CGFloat = CGFloat(position) * -14
        return FileThumbnail(item: item, size: 40, cornerRadius: 7, showsPlayBadge: false)
            .padding(2)
            .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
            .rotationEffect(.degrees(angle))
            .offset(x: shift)
    }

    /// The category's share of the folder's total size.
    private var shareBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: barWidth(in: geometry.size.width))
            }
        }
        .frame(height: 4)
        .help(share > 0 ? "\(Int((share * 100).rounded()))% of this folder’s size" : "")
        .accessibilityHidden(true)
    }

    private func barWidth(in width: CGFloat) -> CGFloat {
        share > 0 ? max(4, width * CGFloat(share)) : 0
    }
}

/// A cleanup suggestion card in the same style as the Library cards, led by
/// the size that could be reviewed.
private struct CleanupCard: View {
    let category: String
    let summary: LibrarySummary
    let action: () -> Void

    @State private var isHovering = false

    private var color: Color { Theme.color(for: category) }
    private var isEmpty: Bool { summary.count == 0 }

    var body: some View {
        Button(action: action) {
            content
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
                .modifier(TintedCard(color: color, isHovering: isHovering,
                                     light: (0.12, 0.03), dark: (0.22, 0.07), restingBorder: 0.15))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .accessibilityLabel("\(Theme.title(for: category)), \(Theme.count(summary.count, "file")), \(Theme.bytes(summary.bytes))")
        .accessibilityHint("Review cleanup candidates")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CategoryBadge(symbol: Theme.icon(for: category), color: color, side: 30, symbolSize: 14, cornerRadius: 8)
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
            amount
            Text(isEmpty ? "Nothing to review" : Theme.count(summary.count, "file") + " to review")
                .contentTransition(.numericText())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var amount: some View {
        let style: AnyShapeStyle = isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        return Text(isEmpty ? "All clear" : Theme.bytes(summary.bytes))
            .contentTransition(.numericText())
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(style)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
