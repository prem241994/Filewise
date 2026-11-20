import AppKit
import FilewiseCore
import QuickLook
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var navigation: FilewiseNavigation
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: Store
    @StateObject private var library = Library()
    @State private var pendingTrash: [FileItem] = []
    @State private var showTrashConfirmation = false
    @State private var showSearchSuggestions = false
    @State private var showRebuildConfirmation = false
    @State private var folderDropTargeted = false
    /// The trial-ended sheet appears by itself once per launch.
    @State private var trialEndedPrompted = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isResultsFocused: Bool

    private var isHome: Bool { library.category == "Home" && library.query.isEmpty }
    private var recentFiles: [FileItem] { Array(library.files.prefix(6)) }

    var body: some View {
        NavigationSplitView {
            SidebarView(library: library) { showRebuildConfirmation = true }
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
                // Hidden on the first-run page, where there are no files to inspect.
                .inspector(isPresented: Binding(get: { navigation.showInspector && library.folder != nil },
                                                set: { navigation.showInspector = $0 })) {
                    inspector.inspectorColumnWidth(min: 240, ideal: 280, max: 380)
                }
        }
        .frame(minWidth: 860, minHeight: 560)
        .focusedSceneObject(library)
        .overlay {
            if folderDropTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !library.isTrashing else {
                library.bannerMessage = "Finish the Trash operation before changing folders."
                return false
            }
            guard urls.count == 1, let url = urls.first, url.isFileURL,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                  values.isDirectory == true, values.isPackage != true else {
                library.bannerMessage = "Drop one folder to scan it."
                return false
            }
            library.selectLocation(url, rememberCustom: true)
            return true
        } isTargeted: { folderDropTargeted = $0 }
        .confirmationDialog("Rebuild the file index?", isPresented: $showRebuildConfirmation) {
            Button("Rebuild Index") { library.rebuildIndex() }
        } message: {
            Text("Filewise will rescan the selected folder. Trash Undo records are kept.")
        }
        .confirmationDialog(trashTitle, isPresented: $showTrashConfirmation, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                library.trashFiles(items: pendingTrash)
                pendingTrash = []
            }
            Button("Cancel", role: .cancel) { pendingTrash = [] }
        } message: {
            Text(trashMessage)
        }
        .sheet(item: $store.paywall) { request in
            PaywallView(store: store, request: request)
        }
        .onAppear {
            focusRequestedSearch()
            // Give the saved folder's scan a moment to start, so the sheet can name its size.
            Task {
                try? await Task.sleep(for: .seconds(1))
                promptIfTrialEnded()
            }
        }
        .onChange(of: store.status) { promptIfTrialEnded() }
        .onChange(of: library.scanning) { promptIfTrialEnded() }
        .onChange(of: navigation.searchRequested) { _, requested in
            if requested { focusRequestedSearch() }
        }
        .onChange(of: settings.largeFileBytes) { library.applySettings(rescan: false) }
        .onChange(of: settings.oldAfterDays) { library.applySettings(rescan: false) }
        .onChange(of: settings.ignoredFolders) { library.applySettings(rescan: true) }
        .quickLookPreview($library.previewURL)
        .sheet(isPresented: $library.isTrashing) {
            TrashProgressDialog(library: library)
        }
        .onKeyPress(.space) {
            guard isResultsFocused, let item = library.selectedFiles.first else { return .ignored }
            library.previewURL = library.previewURL == nil ? item.url : nil
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard isResultsFocused, isHome else { return .ignored }
            moveRecentSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isResultsFocused, isHome else { return .ignored }
            moveRecentSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard isResultsFocused, isHome, !library.selectedIDs.isEmpty else { return .ignored }
            FileActions.open(library.selectedFiles)
            return .handled
        }
        .onKeyPress(.delete) {
            // The results table handles Delete through onDeleteCommand.
            guard isResultsFocused, isHome, !library.selectedIDs.isEmpty else { return .ignored }
            requestTrash(library.selectedFiles)
            return .handled
        }
        .onKeyPress(.escape) {
            if isSearchFocused {
                isSearchFocused = false
                showSearchSuggestions = false
                isResultsFocused = true
                return .handled
            }
            if !library.selectedIDs.isEmpty {
                library.deselectAll()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if let banner = library.bannerMessage {
                bannerView(banner)
                Divider()
            }
            if isHome {
                ScrollViewReader { proxy in
                    ScrollView {
                        HomeView(library: library, recentFiles: recentFiles,
                                 onPreview: preview, onTrash: requestTrash)
                            .padding(Theme.Spacing.page)
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($isResultsFocused)
                    .onChange(of: library.selectedIDs) { _, ids in
                        if ids.count == 1, let id = ids.first {
                            withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id) }
                        }
                    }
                }
            } else {
                ResultsView(library: library, isResultsFocused: $isResultsFocused,
                            onPreview: preview, onTrash: requestTrash)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !library.selectedIDs.isEmpty { selectionBar }
        }
        .navigationTitle(library.folder?.lastPathComponent ?? "Filewise")
        .navigationSubtitle(library.folder == nil ? "" :
            "\(Theme.count(library.files.count, "file")) · \(Theme.bytes(library.summary(for: "Home").bytes))")
        .toolbar {
            ToolbarItem(placement: .principal) { searchField }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let folder = library.folder { library.scan(folder) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Rescan the selected folder")
                .disabled(library.folder == nil || library.scanning)
                Button {
                    navigation.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help(navigation.showInspector ? "Hide file details" : "Show file details")
                .disabled(library.folder == nil)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(Self.searchPrompt, text: $library.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityLabel("Search files")
                .accessibilityHint("Search by name, type, date, size, source, or location")
                .onKeyPress(.downArrow) {
                    let first = isHome ? recentFiles.first : library.visible.first
                    guard let first else { return .ignored }
                    showSearchSuggestions = false
                    isSearchFocused = false
                    isResultsFocused = true
                    if library.selectedIDs.isEmpty { library.selectedIDs = [first.id] }
                    return .handled
                }
                .onSubmit {
                    guard !library.query.isEmpty else { return }
                    library.addRecentSearch(library.query)
                    showSearchSuggestions = false
                }
            if !library.query.isEmpty {
                Button { library.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
            Button { showSearchSuggestions.toggle() } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(showSearchSuggestions ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Search suggestions and recent searches")
            .accessibilityLabel("Search suggestions and recent searches")
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(minWidth: 240, idealWidth: 400, maxWidth: 460, minHeight: 28)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSearchFocused ? Color.accentColor.opacity(0.7) : Theme.hairline)
        )
        .popover(isPresented: $showSearchSuggestions, arrowEdge: .bottom) {
            SearchSuggestionsView(library: library) { selectedQuery in
                library.query = selectedQuery
                library.addRecentSearch(selectedQuery)
                showSearchSuggestions = false
            }
        }
        .onChange(of: isSearchFocused) { _, focused in
            if focused && library.query.isEmpty { showSearchSuggestions = true }
        }
    }

    private func bannerView(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "info.circle.fill").foregroundStyle(.tint)
            Text(message).font(.callout)
            Spacer()
            if library.canUndoTrash {
                Button { library.undoLastTrash() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)
            }
            // Dismissing only hides the message; ⌘Z can still undo.
            Button { library.bannerMessage = nil } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.tint(.accentColor))
    }

    private var selectionBar: some View {
        let selected = library.selectedFiles
        return HStack(spacing: Theme.Spacing.m) {
            Text("\(Theme.count(selected.count, "file")) selected · \(Theme.bytes(selected.reduce(0) { $0 + $1.size }))")
                .font(.callout.weight(.medium))
            Button("Deselect") { library.deselectAll() }
                .buttonStyle(.link)
            Spacer()
            Button { FileActions.reveal(selected) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button(role: .destructive) { requestTrash(selected) } label: {
                Label("Move to Trash…", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(library.isTrashing)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Inspector

    @ViewBuilder private var inspector: some View {
        let selected = library.selectedFiles
        if selected.count == 1, let item = selected.first {
            DetailInspectorView(
                item: item,
                location: library.displayLocation(for: item),
                otherCopies: library.otherCopies(of: item).map { ($0, library.displayLocation(for: $0)) },
                onQuickLook: { preview(item) },
                onTrash: { requestTrash([item]) },
                autoplay: library.playRequestID == item.id
            )
        } else if selected.count > 1 {
            MultiSelectionInspectorView(items: selected) { requestTrash(selected) }
        } else {
            ContentUnavailableView("No Selection", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Select a file to see its details and why it’s suggested."))
        }
    }

    // MARK: - Actions

    private func preview(_ item: FileItem) {
        library.previewURL = item.url
    }

    /// Shows the unlock sheet once when the trial has ended, after any scan,
    /// with the size of the cleanup suggestions it found.
    private func promptIfTrialEnded() {
        guard store.status == .expired, !trialEndedPrompted, store.paywall == nil,
              !library.scanning, !library.isTrashing else { return }
        trialEndedPrompted = true
        let suggestions = library.summary(for: "Clean Up")
        store.paywall = PaywallRequest(bytes: suggestions.bytes, count: suggestions.count, trialEnded: true)
    }

    /// Asks before moving files; after the trial, offers the unlock instead.
    private func requestTrash(_ items: [FileItem]) {
        guard !items.isEmpty, !library.isTrashing else { return }
        store.requireUnlock(bytes: items.reduce(0) { $0 + $1.size }, count: items.count) {
            pendingTrash = items
            showTrashConfirmation = true
        }
    }

    private var trashTitle: String {
        pendingTrash.count == 1
            ? "Move “\(pendingTrash[0].name)” to Trash?"
            : "Move \(Theme.count(pendingTrash.count, "file")) to Trash?"
    }

    /// Names the files being moved so nothing is trashed unseen.
    private var trashMessage: String {
        let size = Theme.bytes(pendingTrash.reduce(0) { $0 + $1.size })
        var message = "\(size) will be moved to the macOS Trash. You can undo this, or restore files from the Trash."
        if pendingTrash.count > 1 {
            let names = pendingTrash.prefix(3).map { "“\($0.name)”" }.joined(separator: ", ")
            let more = pendingTrash.count > 3 ? ", and \(pendingTrash.count - 3) more" : ""
            message = "Includes \(names)\(more).\n\n" + message
        }
        return message
    }

    private func moveRecentSelection(by delta: Int) {
        let items = recentFiles
        guard !items.isEmpty else { return }
        let current = library.selectedIDs.count == 1
            ? items.firstIndex { library.selectedIDs.contains($0.id) } : nil
        let index = current.map { max(0, min(items.count - 1, $0 + delta)) } ?? (delta > 0 ? 0 : items.count - 1)
        library.selectedIDs = [items[index].id]
        if library.previewURL != nil { library.previewURL = items[index].url }
    }

    private static let searchPrompt = "Search files, or try “pdfs from last week”"

    private func focusRequestedSearch() {
        guard navigation.searchRequested else { return }
        DispatchQueue.main.async {
            isSearchFocused = true
            // @FocusState does not reliably reach a text field in the window
            // toolbar, so also make the field first responder directly.
            let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
            if let window, let field = Self.searchField(in: window.contentView?.superview) {
                window.makeFirstResponder(field)
            }
            navigation.searchRequested = false
        }
    }

    /// Finds the toolbar search field, which lives outside the content view.
    private static func searchField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.placeholderString == searchPrompt {
            return field
        }
        for subview in view.subviews {
            if let field = searchField(in: subview) { return field }
        }
        return nil
    }
}
