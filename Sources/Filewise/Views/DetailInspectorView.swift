import AppKit
import FilewiseCore
import SwiftUI

struct DetailInspectorView: View {
    let item: FileItem
    let location: String
    let otherCopies: [(item: FileItem, location: String)]
    let onQuickLook: () -> Void
    let onTrash: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.s) {
                    Image(nsImage: IconCache.shared.icon(for: item))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Text(item.kind.isEmpty ? "FILE" : item.kind.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.subtleFill, in: Capsule())
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    metaRow("Size", item.size < 1000 || (item.kind == "app" && item.size == 0)
                            ? item.displaySize
                            : "\(item.displaySize) (\(item.size.formatted()) bytes)")
                    metaRow("Modified", item.modified.formatted(date: .abbreviated, time: .shortened))
                    if let source = item.downloadSource {
                        metaRow("Downloaded From", source)
                    }
                    metaRow("Location", location)
                        .help(item.url.deletingLastPathComponent().path)
                }

                if !item.cleanupReasons.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        sectionLabel("Why it’s suggested")
                        ForEach(item.cleanupReasons, id: \.self) { reason in
                            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                                Image(systemName: reason.symbol)
                                    .foregroundStyle(Theme.color(for: reason))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(reason.label).font(.callout.weight(.medium))
                                    Text(reason.explanation).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !otherCopies.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        sectionLabel(otherCopies.count == 1 ? "Identical copy" : "Identical copies")
                        ForEach(otherCopies.prefix(5), id: \.item.id) { copy in
                            Button { FileActions.reveal([copy.item]) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(copy.item.name).lineLimit(1).truncationMode(.middle)
                                    Text(copy.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                            .accessibilityHint("Shows this copy in Finder")
                        }
                        if otherCopies.count > 5 {
                            Text("and \(Theme.count(otherCopies.count - 5, "more copy", "more copies"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: Theme.Spacing.s) {
                    Button(action: onQuickLook) {
                        Label("Quick Look", systemImage: "eye").frame(maxWidth: .infinity)
                    }
                    HStack(spacing: Theme.Spacing.s) {
                        Button { FileActions.open([item]) } label: {
                            Label("Open", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                        }
                        Button { FileActions.reveal([item]) } label: {
                            Label("Finder", systemImage: "folder").frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Show in Finder")
                    }
                    Button(role: .destructive, action: onTrash) {
                        Label("Move to Trash…", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.red)
                }
                .controlSize(.large)
            }
            .padding(Theme.Spacing.l)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).lineLimit(3).textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MultiSelectionInspectorView: View {
    let items: [FileItem]
    let onTrash: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(Theme.count(items.count, "file")).font(.headline)
                    Text(Theme.bytes(items.reduce(0) { $0 + $1.size })).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(items.prefix(12)) { item in
                        HStack(spacing: Theme.Spacing.s) {
                            Image(nsImage: IconCache.shared.icon(for: item))
                                .resizable().frame(width: 16, height: 16)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(item.displaySize).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if items.count > 12 {
                        Text("and \(Theme.count(items.count - 12, "more file"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: Theme.Spacing.s) {
                    Button { FileActions.reveal(items) } label: {
                        Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    Button(role: .destructive, action: onTrash) {
                        Label("Move \(Theme.count(items.count, "File")) to Trash…", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.red)
                }
                .controlSize(.large)
            }
            .padding(Theme.Spacing.l)
        }
    }
}
