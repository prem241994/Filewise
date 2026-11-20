import AppKit
import FilewiseCore
import SwiftUI

struct ResultsView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var navigation: FilewiseNavigation
    @EnvironmentObject private var store: Store
    var isResultsFocused: FocusState<Bool>.Binding
    let onPreview: (FileItem) -> Void
    let onTrash: ([FileItem]) -> Void
    /// Views shown as a gallery, stored as comma-separated view names.
    @AppStorage("filewise.gridViews") private var gridViews = "Images,Videos,Screenshots"
    @AppStorage("filewise.keepRule") private var keepRuleValue = KeepRule.oldest.rawValue

    private var keepRule: KeepRule { KeepRule(rawValue: keepRuleValue) ?? .oldest }

    private func selectExtraCopies(keeping rule: KeepRule) {
        keepRuleValue = rule.rawValue
        let extras = DuplicateSelection.extraCopies(in: library.files, keeping: rule)
        let bytes = library.files.reduce(Int64(0)) { extras.contains($1.id) ? $0 + $1.size : $0 }
        store.requireUnlock(bytes: bytes, count: extras.count) {
            library.selectDuplicateCopies(keeping: rule)
        }
    }

    private var layoutKey: String { library.query.isEmpty ? library.category : "Search" }
    private var showsGrid: Bool { gridViews.split(separator: ",").contains { $0 == layoutKey } }

    private func setGrid(_ grid: Bool) {
        var views = Set(gridViews.split(separator: ",").map(String.init))
        if grid { views.insert(layoutKey) } else { views.remove(layoutKey) }
        gridViews = views.sorted().joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.m)
            if library.visible.isEmpty {
                Group {
                    if library.files.isEmpty && !library.scanning && library.scanNotice != nil {
                        ScanNoticeView(library: library).padding(Theme.Spacing.page)
                    } else {
                        ContentUnavailableView(
                            library.query.isEmpty ? "No Files" : "No Matching Files",
                            systemImage: library.query.isEmpty ? Theme.icon(for: library.category) : "magnifyingglass",
                            description: Text(library.scanning ? "Indexing your files…" : emptyMessage))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showsGrid {
                gallery
            } else {
                table
            }
        }
    }

    private var title: String {
        library.query.isEmpty ? Theme.title(for: library.category) : "Results for “\(library.query)”"
    }

    private var emptyMessage: String {
        library.query.isEmpty ? "Nothing in this folder matches this view." : "Try another word, or a phrase like “large videos”."
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title).font(Theme.pageTitle).lineLimit(1).accessibilityAddTraits(.isHeader)
                Text("\(Theme.count(library.visible.count, "file")) · \(Theme.bytes(library.visible.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !library.visible.isEmpty {
                Picker("View", selection: Binding(get: { showsGrid }, set: { setGrid($0) })) {
                    Image(systemName: "list.bullet").accessibilityLabel("List").tag(false)
                    Image(systemName: "square.grid.2x2").accessibilityLabel("Grid").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show as a list or as a grid of previews")
            }
            if library.category == "Duplicates" && library.query.isEmpty && !library.visible.isEmpty {
                keepRuleMenu
            }
        }
    }

    private var table: some View {
        Table(library.visible, selection: $library.selectedIDs, sortOrder: $library.sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                FileNameCell(item: item, location: library.displayLocation(for: item))
            }
            .width(min: 220, ideal: 380)
            TableColumn("Notes") { item in
                ReasonTags(reasons: item.cleanupReasons)
            }
            .width(min: 90, ideal: 190)
            TableColumn("Size", value: \.size) { item in
                Text(item.displaySize).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Modified", value: \.modified) { item in
                Text(item.modified.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
        .focused(isResultsFocused)
        .contextMenu(forSelectionType: String.self) { ids in
            FileMenuItems(items: items(ids), onPreview: onPreview, onTrash: onTrash)
        } primaryAction: { ids in
            FileActions.open(items(ids))
        }
        .onDeleteCommand {
            let selected = library.selectedFiles
            if !selected.isEmpty { onTrash(selected) }
        }
        .accessibilityLabel("Files")
    }

    /// Click selects extra copies with the last rule; the menu picks another.
    private var keepRuleMenu: some View {
        Menu {
            Section("Keep in Each Group") {
                ruleButton("Oldest Copy", .oldest)
                ruleButton("Newest Copy", .newest)
                ruleButton("Shortest Name", .shortestName)
            }
            let folders = library.foldersWithDuplicates.prefix(8)
            if !folders.isEmpty {
                Section("Keep the Copy In") {
                    ForEach(Array(folders), id: \.self) { folder in
                        ruleButton(folderLabel(folder), .inFolder(folder))
                    }
                }
            }
        } label: {
            Label("Select Extra Copies", systemImage: "checklist")
        } primaryAction: {
            selectExtraCopies(keeping: keepRule)
        }
        .fixedSize()
        .help("Selects every copy except the \(keepRule.summary) in each group of identical files. Use the arrow to choose which copy to keep.")
    }

    private func ruleButton(_ title: String, _ rule: KeepRule) -> some View {
        Button { selectExtraCopies(keeping: rule) } label: {
            if rule == keepRule { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// "Desktop › Downloads", relative to the selected folder.
    private func folderLabel(_ path: String) -> String {
        let probe = FileItem(url: URL(fileURLWithPath: path).appendingPathComponent("x"), size: 0, modified: .distantPast,
                             changed: nil, duplicate: false, hash: nil, downloadSource: nil)
        return library.displayLocation(for: probe)
    }

    // MARK: - Gallery

    private var gallery: some View {
        GeometryReader { geometry in
            let side: CGFloat = 150
            let spacing = Theme.Spacing.l
            let columns = max(1, Int((geometry.size.width - 2 * Theme.Spacing.page + spacing) / (side + 6 + spacing)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(side + 6), spacing: spacing), count: columns),
                              alignment: .leading, spacing: spacing) {
                        ForEach(library.visible) { item in
                            MediaTile(item: item, side: side, isSelected: library.selectedIDs.contains(item.id),
                                      onPlay: { play(item) })
                                .id(item.id)
                                .onTapGesture(count: 2) { FileActions.open([item]) }
                                .onTapGesture { select(item) }
                                .contextMenu {
                                    FileMenuItems(items: contextItems(for: item), onPreview: onPreview, onTrash: onTrash)
                                }
                                .accessibilityAction { select(item) }
                                .fileAccessibilityActions(item, onPreview: onPreview, onTrash: onTrash)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .focusable()
                .focusEffectDisabled()
                .focused(isResultsFocused)
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                    moveSelection(press.key, columns: columns)
                }
                .onKeyPress(.return) {
                    guard !library.selectedIDs.isEmpty else { return .ignored }
                    FileActions.open(library.selectedFiles)
                    return .handled
                }
                .onDeleteCommand {
                    let selected = library.selectedFiles
                    if !selected.isEmpty { onTrash(selected) }
                }
                .onChange(of: library.selectedIDs) { _, ids in
                    if ids.count == 1, let id = ids.first {
                        withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
                .accessibilityLabel("Files")
            }
        }
    }

    private func play(_ item: FileItem) {
        isResultsFocused.wrappedValue = true
        navigation.showInspector = true
        library.play(item)
    }

    /// Click selects one file; ⌘-click adds or removes it.
    private func select(_ item: FileItem) {
        isResultsFocused.wrappedValue = true
        if NSEvent.modifierFlags.contains(.command) {
            library.toggleSelection(for: item)
        } else {
            library.selectedIDs = [item.id]
        }
    }

    /// A context menu acts on the whole selection when the clicked file is in it.
    private func contextItems(for item: FileItem) -> [FileItem] {
        library.selectedIDs.contains(item.id) && library.selectedIDs.count > 1 ? library.selectedFiles : [item]
    }

    private func moveSelection(_ key: KeyEquivalent, columns: Int) -> KeyPress.Result {
        let items = library.visible
        guard !items.isEmpty else { return .ignored }
        let delta = switch key {
        case .leftArrow: -1
        case .rightArrow: 1
        case .upArrow: -columns
        default: columns
        }
        let current = library.selectedIDs.count == 1 ? items.firstIndex { library.selectedIDs.contains($0.id) } : nil
        let index = current.map { max(0, min(items.count - 1, $0 + delta)) } ?? 0
        library.selectedIDs = [items[index].id]
        if library.previewURL != nil { library.previewURL = items[index].url }
        return .handled
    }

    private func items(_ ids: Set<String>) -> [FileItem] {
        ids.compactMap { library.filesByID[$0] }.sorted { $0.modified > $1.modified }
    }
}
