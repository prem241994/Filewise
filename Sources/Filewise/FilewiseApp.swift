import SwiftUI
import AppKit

@main
struct FilewiseApp: App {
    @StateObject private var navigation = FilewiseNavigation()
    var body: some Scene {
        Window("Filewise", id: "main") { ContentView().environmentObject(navigation).preferredColorScheme(.light) }
            .commands { CommandGroup(replacing: .newItem) { } }
        MenuBarExtra("Filewise", systemImage: "folder.badge.magnifyingglass") {
            FilewiseMenu().environmentObject(navigation)
        }
    }
}

final class FilewiseNavigation: ObservableObject {
    @Published var searchRequested = false
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
