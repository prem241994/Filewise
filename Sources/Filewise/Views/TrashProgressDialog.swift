import SwiftUI

struct TrashProgressDialog: View {
    @ObservedObject var library: Library
    private let muted = Color.secondary

    private var percentage: Int {
        guard library.trashTotalCount > 0 else { return 0 }
        let pct = Int((Double(library.trashCurrentCount) / Double(library.trashTotalCount)) * 100)
        return min(100, max(0, pct))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(library.trashIsCompleted ? Color.green.opacity(0.14) : Color.red.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: library.trashIsCompleted ? "checkmark.circle.fill" : "trash.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(library.trashIsCompleted ? .green : .red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(library.trashIsCompleted ? "Move to Trash Complete" : "Moving to Trash…")
                        .font(.system(size: 18, weight: .bold))
                    Text(library.trashIsCompleted
                         ? "\(library.trashCurrentCount.formatted()) of \(library.trashTotalCount.formatted()) files moved to macOS Trash."
                         : "Processed \(library.trashCurrentCount.formatted()) of \(library.trashTotalCount.formatted()) files (\(percentage)%)")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
            }

            // Custom, solid Progress Bar (never glitches or disappears at 100%)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.hairline)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(library.trashIsCompleted ? Color.green : Color.blue)
                        .frame(
                            width: max(0, min(geo.size.width, geo.size.width * CGFloat(library.trashIsCompleted ? 100 : percentage) / 100.0)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trash progress")
            .accessibilityValue(library.trashIsCompleted
                ? "Complete, \(library.trashCurrentCount) of \(library.trashTotalCount) files moved"
                : "\(percentage) percent, \(library.trashCurrentCount) of \(library.trashTotalCount) files processed")

            // Status Card
            VStack(alignment: .leading, spacing: 7) {
                if !library.trashIsCompleted {
                    HStack {
                        Text("Current:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        Text(library.trashCurrentName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Text("Size moved to Trash:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        Text(ByteCountFormatter.string(fromByteCount: library.trashBytesMoved, countStyle: .file))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                } else {
                    HStack {
                        Text("Total files moved:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        Text("\(library.trashCurrentCount.formatted()) files")
                            .font(.caption.weight(.semibold))
                    }

                    HStack {
                        Text("Total size moved to Trash:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        Text(ByteCountFormatter.string(fromByteCount: library.trashBytesMoved, countStyle: .file))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Text("Location:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(muted)
                        Text("macOS Trash — files remain there until emptied")
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    if library.trashFailedCount > 0 {
                        Text("\(library.trashFailedCount.formatted()) files could not be moved.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10))

            // Action Buttons
            HStack {
                Spacer()
                if library.trashIsCompleted {
                    Button("Done") {
                        library.isTrashing = false
                        library.trashIsCompleted = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        library.cancelTrashing()
                    }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.regular)
                }
            }
        }
        .padding(26)
        .frame(width: 460)
    }
}
