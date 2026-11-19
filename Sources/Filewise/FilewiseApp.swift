import AppKit
import FilewiseCore
import SwiftUI

@main
struct FilewiseApp: App {
    @StateObject private var navigation = FilewiseNavigation()

    init() {
        #if FILEWISE_SNAPSHOT
        SnapshotHook.install()
        #endif
    }

    var body: some Scene {
        Window("Filewise", id: "main") {
            ContentView().environmentObject(navigation)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            SidebarCommands()
            FilewiseCommands()
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
private struct FilewiseCommands: Commands {
    @FocusedObject private var library: Library?

    var body: some Commands {
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
