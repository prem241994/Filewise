import AppKit
import FilewiseCore
import SwiftUI

@main
struct FilewiseApp: App {
    @StateObject private var navigation = FilewiseNavigation()
    @StateObject private var settings = AppSettings()

    init() {
        #if FILEWISE_SNAPSHOT
        SnapshotHook.install()
        #endif
    }

    var body: some Scene {
        Window("Filewise", id: "main") {
            ContentView()
                .environmentObject(navigation)
                .environmentObject(settings)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            SidebarCommands()
            FilewiseCommands(navigation: navigation)
        }
        Settings {
            SettingsView().environmentObject(settings)
        }
        MenuBarExtra("Filewise", systemImage: "folder.badge.magnifyingglass") {
            FilewiseMenu().environmentObject(navigation)
        }
    }
}

@MainActor
final class FilewiseNavigation: ObservableObject {
    @Published var searchRequested = false
    @Published var showInspector = true
}

/// Menu bar commands that act on the focused window's library.
/// Keyboard shortcuts with ⌘ must live here: macOS offers them to the menu
/// bar before the window, so a view's key handler never sees them.
private struct FilewiseCommands: Commands {
    @FocusedObject private var library: Library?
    let navigation: FilewiseNavigation

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { undo() }
                .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        // Replaces the text Find menu: the search field is the app's Find.
        CommandGroup(replacing: .textEditing) {
            Button("Search Files") { navigation.searchRequested = true }
                .keyboardShortcut("f")
        }
        CommandGroup(replacing: .newItem) {
            Button("Choose Folder…") { library?.chooseFolder() }
                .keyboardShortcut("o")
                .disabled(library == nil)
        }
        CommandGroup(after: .undoRedo) {
            Button("Restore Last Trashed Files") { library?.undoLastTrash() }
                .disabled(library?.canUndoTrash != true)
        }
        CommandGroup(before: .sidebar) {
            Button("Refresh Library") {
                if let library, let folder = library.folder { library.scan(folder) }
            }
            .keyboardShortcut("r")
            .disabled(library?.folder == nil || library?.scanning == true)
            Divider()
        }
    }
}

extension FilewiseCommands {
    /// Undoes typing while a text field is being edited; otherwise restores
    /// the last batch moved to Trash.
    private func undo() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        } else if library?.canUndoTrash == true {
            library?.undoLastTrash()
        }
    }
}

private struct FilewiseMenu: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var navigation: FilewiseNavigation

    var body: some View {
        Button("Open Filewise") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Search Files") {
            navigation.searchRequested = true
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Filewise") { NSApp.terminate(nil) }
    }
}
