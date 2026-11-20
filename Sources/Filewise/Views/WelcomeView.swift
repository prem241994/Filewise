import SwiftUI

/// The first-run page, shown on Home until a folder is chosen. It explains
/// what Filewise does and offers Downloads, which the sandbox can read
/// without asking, as a one-click start.
struct WelcomeView: View {
    @ObservedObject var library: Library

    private var downloads: URL {
        FolderAccess.homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Filewise finds files by name, type, date, or size, and shows what you can safely clean up.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                point("magnifyingglass", .blue, "Find anything quickly",
                      "Search in plain words, such as “pdfs from last week” or “large videos”.")
                point("sparkles", .orange, "Clean up with confidence",
                      "See duplicates, old downloads, and large files. Files go to the Trash, and you can undo.")
                point("lock.shield", .green, "Private by design",
                      "Filewise works only with folders you choose, and nothing leaves your Mac.")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        library.selectLocation(downloads)
                    } label: {
                        Label("Scan Downloads", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Scans your Downloads folder")

                    Button("Choose Another Folder…") { library.chooseFolder() }
                }
                .controlSize(.large)
                Text("You can also drop a folder onto this window. Change folders anytime from the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.xl + Theme.Spacing.s)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
    }

    private func point(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(Theme.tint(color), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
