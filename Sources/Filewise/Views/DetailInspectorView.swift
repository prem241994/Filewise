import AppKit
import SwiftUI
import QuickLook

struct DetailInspectorView: View {
    let item: FileItem
    let onClose: () -> Void
    let onQuickLook: () -> Void
    let onTrash: () -> Void

    private let muted = Color.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("File Details").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close file details")
            }
            .padding(.bottom, 2)

            // Large Icon & File Name
            VStack(spacing: 12) {
                Image(nsImage: IconCache.shared.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                VStack(spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Text(item.kind.uppercased() + (item.kind.isEmpty ? "FILE" : " FILE"))
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.05), in: Capsule())
                        .foregroundStyle(muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Divider()

            // Metadata rows
            VStack(alignment: .leading, spacing: 13) {
                metaRow(title: "Size", value: item.kind == "app" && item.size == 0 ? item.displaySize : item.displaySize + " (\(item.size.formatted()) bytes)")
                metaRow(title: "Modified", value: item.modified.formatted(date: .abbreviated, time: .shortened))
                if let changed = item.changed {
                    metaRow(title: "Attributes Changed", value: changed.formatted(date: .abbreviated, time: .shortened))
                }
                if let source = item.downloadSource {
                    metaRow(title: "Downloaded From", value: source)
                }
                metaRow(title: "Location", value: item.url.deletingLastPathComponent().path)
            }

            // Duplicate status
            if item.duplicate {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "square.on.square")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duplicate Copy")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("An identical copy exists in your library.")
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            Spacer()

            // Quick Actions
            VStack(spacing: 8) {
                Button(action: onQuickLook) {
                    Label("Quick Look", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(item.url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Label("Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Show in Finder")
                }

                Button(role: .destructive, action: onTrash) {
                    Label("Move to Trash", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 270)
        .background(Color(white: 0.985))
    }

    private func metaRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(muted)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
