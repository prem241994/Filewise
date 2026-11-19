import AppKit
import FilewiseCore
import SwiftUI

/// Filewise → Settings… (⌘,)
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedFolder: String?

    var body: some View {
        Form {
            Section {
                Picker("Large files are at least", selection: $settings.largeFileBytes) {
                    ForEach(AppSettings.largeFileChoices, id: \.self) { bytes in
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).tag(bytes)
                    }
                }
                Picker("Screenshots and downloads are old after", selection: $settings.oldAfterDays) {
                    ForEach(AppSettings.oldAfterChoices, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
            } header: {
                Text("Cleanup Suggestions")
            } footer: {
                Text("A download counts as old only if it was neither opened nor changed in that time.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if settings.ignoredFolders.isEmpty {
                    Text("No folders are ignored.").foregroundStyle(.secondary)
                } else {
                    List(settings.ignoredFolders, id: \.self, selection: $selectedFolder) { path in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Text(URL(fileURLWithPath: path).deletingLastPathComponent().path)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                        } icon: {
                            Image(systemName: "folder.badge.minus").foregroundStyle(.secondary)
                        }
                        .help(path)
                    }
                    .frame(minHeight: 90)
                }
                HStack {
                    Button("Add Folder…", action: addFolder)
                    Button("Remove") {
                        if let selectedFolder { settings.stopIgnoring(selectedFolder) }
                        selectedFolder = nil
                    }
                    .disabled(selectedFolder == nil)
                }
            } header: {
                Text("Ignored Folders")
            } footer: {
                Text("Scans skip these folders and everything inside them.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("Filewise keeps your file index on this Mac and never sends file names or contents anywhere.",
                      systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Restore Defaults") { settings.resetToDefaults() }
                    .disabled(settings.isDefault)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        panel.message = "Choose folders for Filewise to skip when scanning."
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(settings.ignore)
    }
}
