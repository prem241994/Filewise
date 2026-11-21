import FilewiseCore
import SwiftUI

/// The Home page's "Space" card: a ring showing how the folder's size splits
/// across the Library categories, a legend that opens each category, and a
/// bar for the disk the folder is on (used and free).
struct SpaceRingView: View {
    @ObservedObject var library: Library

    @State private var disk: DiskSpace?
    @State private var highlighted: String?
    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let otherTitle = "Other"

    private struct Slice: Identifiable {
        let title: String
        let summary: LibrarySummary
        let start: Double
        let end: Double
        var id: String { title }
        var share: Double { end - start }
    }

    private var total: Int64 { library.summary(for: "Home").bytes }

    /// One slice per non-empty category, largest first, then "Other" for files
    /// outside the Library categories.
    private var slices: [Slice] {
        let total = total
        guard total > 0 else { return [] }
        var parts = Theme.libraryCategories
            .map { ($0, library.summary(for: $0)) }
            .filter { $0.1.bytes > 0 }
            .sorted { $0.1.bytes > $1.1.bytes }
        var other = library.summary(for: "Home")
        for (_, summary) in parts {
            other.count -= summary.count
            other.bytes -= summary.bytes
        }
        if other.bytes > 0 { parts.append((Self.otherTitle, other)) }
        var start = 0.0
        return parts.map { title, summary in
            let end = min(1, start + Double(summary.bytes) / Double(total))
            defer { start = end }
            return Slice(title: title, summary: summary, start: start, end: end)
        }
    }

    var body: some View {
        let slices = slices
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .center, spacing: 28) {
                ring(slices)
                legend(slices).accessibilitySortPriority(1)
            }
            .accessibilityElement(children: .contain)
            if let disk { diskBar(disk) }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .task(id: "\(library.folder?.path ?? "")|\(total)") {
            guard let folder = library.folder else { disk = nil; return }
            disk = await Task.detached { DiskSpace(for: folder) }.value
        }
        .onAppear {
            if reduceMotion { progress = 1 } else {
                withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
            }
        }
    }

    // MARK: - Ring

    private func ring(_ slices: [Slice]) -> some View {
        let focus = slices.first { $0.title == highlighted }
        return ZStack {
            Circle().stroke(Theme.subtleFill, lineWidth: 22)
            ForEach(slices) { slice in
                // A small gap between slices, unless the slice is too thin to show one.
                let gap = slices.count > 1 && slice.share > 0.02 ? 0.004 : 0
                Circle()
                    .trim(from: (slice.start + gap) * progress, to: max(slice.start + gap, slice.end - gap) * progress)
                    .stroke(color(slice.title),
                            style: StrokeStyle(lineWidth: highlighted == slice.title ? 28 : 22, lineCap: .butt))
                    .opacity(highlighted == nil || highlighted == slice.title ? 1 : 0.35)
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(Theme.bytes(focus?.summary.bytes ?? total))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(focus.map { "\(percent($0.share)) · \($0.title)" } ?? "in this folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 110)
        }
        .frame(width: 168, height: 168)
        .padding(4)
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Space used in this folder: \(Theme.bytes(total))")
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(slices.map { "\($0.title) \(percent($0.share))" }.joined(separator: ", "))
    }

    // MARK: - Legend

    private func legend(_ slices: [Slice]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Space").font(Theme.sectionTitle).accessibilityAddTraits(.isHeader)
                .padding(.bottom, Theme.Spacing.xs)
            if slices.isEmpty {
                Text(library.scanning ? "Measuring your files…" : "No files yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(slices) { slice in
                legendRow(slice)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func legendRow(_ slice: Slice) -> some View {
        let opensCategory = slice.title != Self.otherTitle
        let row = HStack(spacing: Theme.Spacing.s) {
            Circle().fill(color(slice.title)).frame(width: 10, height: 10)
            Text(slice.title).fontWeight(.medium)
            Spacer(minLength: Theme.Spacing.m)
            Text(Theme.bytes(slice.summary.bytes)).monospacedDigit()
            Text(percent(slice.share))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 5)
        .background(highlighted == slice.title ? color(slice.title).opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { highlighted = slice.title } else if highlighted == slice.title { highlighted = nil }
        }

        return Group {
            if opensCategory {
                Button { library.category = slice.title } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows files in this category")
            } else {
                row.help("Files that aren’t images, videos, music, documents, archives, or apps")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slice.title), \(Theme.bytes(slice.summary.bytes)), \(percent(slice.share)) of this folder")
        .accessibilityAddTraits(opensCategory ? .isButton : [])
    }

    // MARK: - Disk

    private func diskBar(_ disk: DiskSpace) -> some View {
        let folderShare = disk.total > 0 ? min(1, Double(total) / Double(disk.total)) : 0
        let usedShare = disk.total > 0 ? min(1, Double(disk.total - disk.available) / Double(disk.total)) : 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Label(disk.name, systemImage: "internaldrive")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(Theme.bytes(disk.available)) free of \(Theme.bytes(disk.total))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.subtleFill)
                    Capsule().fill(Color.secondary.opacity(0.35))
                        .frame(width: geometry.size.width * usedShare * progress)
                    Capsule().fill(Color.accentColor)
                        .frame(width: folderShare > 0 ? max(4, geometry.size.width * folderShare * progress) : 0)
                }
            }
            .frame(height: 8)
            HStack(spacing: Theme.Spacing.m) {
                key(.accentColor, "This folder")
                key(Color.secondary.opacity(0.35), "Everything else")
                key(Theme.subtleFill, "Free")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(disk.name): \(Theme.bytes(disk.available)) free of \(Theme.bytes(disk.total)). This folder uses \(Theme.bytes(total)).")
        .accessibilityAddTraits(.isStaticText)
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
            Text(title)
        }
    }

    // MARK: - Helpers

    private func color(_ title: String) -> Color {
        title == Self.otherTitle ? .gray : Theme.color(for: title)
    }

    private func percent(_ share: Double) -> String {
        if share > 0 && share < 0.01 { return "<1%" }
        return "\(Int((share * 100).rounded()))%"
    }
}

/// Capacity of the volume a folder is on. Reading it needs only access to the
/// folder, so it works inside the App Sandbox.
struct DiskSpace: Sendable, Equatable {
    let name: String
    let total: Int64
    let available: Int64

    init?(for folder: URL) {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        guard let values = try? folder.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        name = values.volumeLocalizedName ?? "Disk"
        self.total = Int64(total)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        available = important > 0 ? important : Int64(values.volumeAvailableCapacity ?? 0)
    }
}
