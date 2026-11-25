import FilewiseCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var store: Store
    let onRebuildIndex: () -> Void

    /// Choosing a sidebar item leaves search, so the selected view is what shows.
    private var selection: Binding<String?> {
        Binding(
            get: { library.category },
            set: { value in
                guard let value else { return }
                library.query = ""
                library.category = value
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            list
            trialBanner
            statusFooter
        }
    }

    private var list: some View {
        List(selection: selection) {
            Section {
                row("Home")
                row("Recents", count: library.summary(for: "Recents").count)
            }
            Section("Library") {
                ForEach(Theme.libraryCategories, id: \.self) { category in
                    row(category, count: library.summary(for: category).count)
                }
            }
            Section("Clean Up") {
                row("Clean Up", title: "Suggestions", count: library.summary(for: "Clean Up").count)
                row("Duplicates", count: library.summary(for: "Duplicates").count)
                row("Large Files", count: library.summary(for: "Large Files").count)
                row("Screenshots", count: library.summary(for: "Screenshots").count)
                row("Downloads", count: library.summary(for: "Downloads").count)
                row("Downloaded From", title: "By Source",
                    count: library.summary(for: "Downloaded From").count)
            }
            Section("Locations") {
                ForEach(locations, id: \.url) { location in
                    locationRow(location.name, icon: location.icon, url: location.url)
                }
                Button { library.chooseFolder() } label: {
                    Label("Other Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose a folder to scan")
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ category: String, title: String? = nil, count: Int? = nil) -> some View {
        Label(title ?? category, systemImage: Theme.icon(for: category))
            .badge(count ?? 0)
            .tag(category)
            .accessibilityValue(count.map { Theme.count($0, "item") } ?? "")
    }

    private var locations: [(name: String, icon: String, url: URL)] {
        // The real home folder; in the sandbox FileManager points into the container.
        let home = FolderAccess.homeDirectory
        var result: [(name: String, icon: String, url: URL)] = [
            ("Desktop", "menubar.dock.rectangle", home.appendingPathComponent("Desktop", isDirectory: true)),
            ("Downloads", "arrow.down.circle", home.appendingPathComponent("Downloads", isDirectory: true)),
            ("Documents", "doc.text", home.appendingPathComponent("Documents", isDirectory: true)),
        ]
        if let custom = library.customFolder, !result.contains(where: { $0.url.path == custom.path }) {
            result.append((custom.lastPathComponent, "folder", custom))
        }
        return result
    }

    private func locationRow(_ name: String, icon: String, url: URL) -> some View {
        let isSelected = library.folder?.path == url.path
        return Button { library.selectLocation(url) } label: {
            HStack {
                Label(name, systemImage: icon)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) folder")
        .accessibilityValue(isSelected ? "Selected location" : "")
        .accessibilityHint("Scans this folder")
    }

    /// The trial offer or the days left. When it has ended, the unlock sheet appears
    /// by itself instead (see ContentView).
    @ViewBuilder private var trialBanner: some View {
        let banner: (text: String, action: String)? = switch store.status {
        case .trial(let days): ("Trial: \(Theme.count(days, "day")) left", "Unlock")
        case .notStarted: ("Free \(License.trialDays)-day trial", "Start")
        default: nil
        }
        if let banner {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: store.status == .notStarted ? "gift" : "sparkles").foregroundStyle(Color.accentColor)
                Text(banner.text).lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                // Both open the sheet, which shows the trial terms before it starts.
                Button(banner.action) { store.showUnlock() }
                    .buttonStyle(.link)
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.tint(.accentColor),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.s)
            .accessibilityElement(children: .combine)
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if library.scanning {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(Theme.count(library.scannedCount, "file"))…")
                    Spacer()
                    Button("Cancel") { library.cancelScan() }
                        .buttonStyle(.link)
                }
            } else if let reading = library.textReading {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Reading text in screenshots… \(reading.done.formatted()) of \(reading.total.formatted())")
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(library.status).lineLimit(2)
                if let date = library.lastSuccessfulScan {
                    Text("Indexed \(date.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.tertiary)
                }
            }
            if library.indexUnavailable && !library.scanning {
                Button("Rebuild Index…", action: onRebuildIndex)
                    .disabled(library.isTrashing)
                Button("Export Undo Records…") { library.exportUndoRecords() }
                Button("Show Index Folder") { library.revealIndex() }
                Text("If rebuilding fails, the original database is kept in this folder.")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.link)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }
}
