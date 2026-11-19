import FilewiseCore
import SwiftUI

struct ResultsView: View {
    @ObservedObject var library: Library
    var isResultsFocused: FocusState<Bool>.Binding
    let onPreview: (FileItem) -> Void
    let onTrash: ([FileItem]) -> Void

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
                Text(title).font(Theme.pageTitle).lineLimit(1)
                Text("\(Theme.count(library.visible.count, "file")) · \(Theme.bytes(library.visible.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if library.category == "Duplicates" && library.query.isEmpty && !library.visible.isEmpty {
                Button { library.selectDuplicateCopies() } label: {
                    Label("Select Extra Copies", systemImage: "checklist")
                }
                .help("Selects every copy except the oldest file in each group of identical files")
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

    private func items(_ ids: Set<String>) -> [FileItem] {
        ids.compactMap { library.filesByID[$0] }.sorted { $0.modified > $1.modified }
    }
}
