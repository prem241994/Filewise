import AppKit
import QuickLook
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var navigation: FilewiseNavigation
    @StateObject private var library = Library()
    @State private var showInspector = true
    @State private var showTrashConfirmation = false
    @State private var singleItemToTrash: FileItem?
    @State private var showSingleTrashConfirmation = false
    @State private var showSearchSuggestions = false
    @State private var showRebuildConfirmation = false
    @State private var folderDropTargeted = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isResultsFocused: Bool
    private let muted = Color.secondary
    private let categories = ["Images", "Videos", "Music", "Documents", "Archives", "Apps"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let banner = library.bannerMessage {
                    bannerView(banner)
                    Divider()
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if library.category == "Home" && library.query.isEmpty {
                                home
                            } else {
                                results
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(30)
                    }
                    .focusable()
                    .focused($isResultsFocused)
                    .onChange(of: library.inspectedItem?.id) { _, id in
                        if let id {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                if !library.selectedIDs.isEmpty {
                    selectionBottomBar
                }
            }
            if showInspector, let inspected = library.inspectedItem {
                Divider()
                DetailInspectorView(
                    item: inspected,
                    onClose: { library.inspectedItem = nil },
                    onQuickLook: { library.previewURL = inspected.url },
                    onTrash: {
                        singleItemToTrash = inspected
                        showSingleTrashConfirmation = true
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .background(.white)
        .frame(minWidth: 1100, minHeight: 700)
        .overlay {
            if folderDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.blue, lineWidth: 4)
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
        } isTargeted: { targeted in
            folderDropTargeted = targeted
        }
        .confirmationDialog("Rebuild the file index?", isPresented: $showRebuildConfirmation) {
            Button("Rebuild Index") { library.rebuildIndex() }
        } message: {
            Text("Filewise will rescan the selected folder. Trash Undo records are kept.")
        }
        .onAppear { focusRequestedSearch() }
        .onChange(of: navigation.searchRequested) { _, requested in
            if requested { focusRequestedSearch() }
        }
        .quickLookPreview($library.previewURL)
        .sheet(isPresented: $library.isTrashing) {
            TrashProgressDialog(library: library)
        }
        .onKeyPress(.space) {
            guard isResultsFocused else { return .ignored }
            if let inspected = library.inspectedItem {
                if library.previewURL == nil {
                    library.previewURL = inspected.url
                } else {
                    library.previewURL = nil
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            guard isResultsFocused else { return .ignored }
            moveSelection(delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isResultsFocused else { return .ignored }
            moveSelection(delta: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard isResultsFocused, let inspected = library.inspectedItem else { return .ignored }
            NSWorkspace.shared.open(inspected.url)
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
        .onKeyPress(.delete) {
            guard isResultsFocused else { return .ignored }
            if !library.selectedIDs.isEmpty {
                showTrashConfirmation = true
                return .handled
            }
            if let inspected = library.inspectedItem {
                singleItemToTrash = inspected
                showSingleTrashConfirmation = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress { press in
            if press.modifiers.contains(.command) && press.characters.lowercased() == "z" && library.canUndoTrash {
                library.undoLastTrash()
                return .handled
            }
            if press.modifiers.contains(.command) && press.characters.lowercased() == "f" {
                isSearchFocused = true
                return .handled
            }
            if press.modifiers.contains(.command) && press.characters.lowercased() == "a" && isResultsFocused {
                library.selectAllVisible()
                return .handled
            }
            return .ignored
        }
        .confirmationDialog(
            "Move \(library.selectedIDs.count) files to Trash?",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                library.trashSelectedFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(library.selectedIDs.count) files (\(bytes(library.selectedBytes))) to the macOS Trash. You can restore them from the Trash if needed.")
        }
        .confirmationDialog(
            "Move \"\(singleItemToTrash?.name ?? "file")\" to Trash?",
            isPresented: $showSingleTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = singleItemToTrash {
                    library.trashFiles(items: [item])
                    singleItemToTrash = nil
                }
            }
            Button("Cancel", role: .cancel) {
                singleItemToTrash = nil
            }
        } message: {
            Text("This file will be moved to the macOS Trash. You can restore it from the Trash if needed.")
        }
    }

    private func focusRequestedSearch() {
        guard navigation.searchRequested else { return }
        DispatchQueue.main.async {
            isSearchFocused = true
            navigation.searchRequested = false
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 9) {
                Image(systemName: "folder.fill").foregroundStyle(.blue)
                Text("Filewise").font(.system(size: 21, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 10).padding(.bottom, 23)
            ScrollView(.vertical) {
              VStack(alignment: .leading, spacing: 1) {
            side("Home", "house")
            side("Recents", "clock")
            Spacer().frame(height: 11)
            ForEach(categories, id: \.self) { side($0, icon($0), count: library.summary(for: $0).count) }
            Divider().padding(.vertical, 12)
            side("Large Files", "externaldrive", count: library.summary(for: "Large Files").count)
            side("Screenshots", "camera.viewfinder", count: library.summary(for: "Screenshots").count)
            side("Duplicates", "square.on.square", count: library.summary(for: "Duplicates").count)
            side("Clean Up", "sparkles", count: library.summary(for: "Clean Up").count)
            side("Downloads", "arrow.down.circle", count: library.summary(for: "Downloads").count)
            side("Downloaded From", "network", count: library.downloadSources.values.reduce(0) { $0 + $1.count })
            Divider().padding(.vertical, 12)
            Text("LOCATIONS").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(muted).padding(.horizontal, 10).padding(.bottom, 7)
            ForEach(quickLocations, id: \.name) { loc in
                locationRow(name: loc.name, icon: loc.icon, url: loc.url)
            }
            if let custom = customFolderLocation {
                locationRow(name: custom.lastPathComponent, icon: "folder.fill", url: custom)
            }
            Button { library.chooseFolder() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder.badge.plus").frame(width: 17).foregroundStyle(muted)
                    Text("Other Folder…").font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 11).frame(height: 30)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 14)
            if library.scanning { ProgressView().padding(.bottom, 8) }
            Text(library.scanning ? "Scanning \(library.scannedCount.formatted()) files…" : library.status)
                .font(.caption).foregroundStyle(muted).lineLimit(2)
            if let date = library.lastSuccessfulScan {
                Text("Last indexed: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(muted)
            }
            if library.indexUnavailable && !library.scanning {
                Button("Rebuild Index…") { showRebuildConfirmation = true }
                    .disabled(library.isTrashing)
                    .buttonStyle(.link).font(.caption)
                Button("Export Undo Records…") { library.exportUndoRecords() }
                    .buttonStyle(.link).font(.caption)
                Button("Show Index Folder") { library.revealIndex() }
                    .buttonStyle(.link).font(.caption)
                Text("If rebuilding fails, the original database is kept in this folder.")
                    .font(.caption2).foregroundStyle(muted)
            }
            if library.scanning {
                Button("Cancel scan") { library.cancelScan() }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(19).padding(.top, 17)
        .frame(width: 240).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.985))
    }

    private func side(_ title: String, _ symbol: String, count: Int? = nil) -> some View {
        Button { library.category = title } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).frame(width: 17).foregroundStyle(muted)
                Text(title)
                Spacer()
                if let count { Text(count.formatted()).font(.caption).foregroundStyle(muted) }
            }
            .font(.system(size: 13, weight: library.category == title ? .semibold : .regular))
            .padding(.horizontal, 11).frame(height: 35)
            .background(library.category == title ? Color.black.opacity(0.05) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(library.category == title ? "Selected" : "Not selected")\(count.map { ", \($0) items" } ?? "")")
    }

    private var quickLocations: [(name: String, icon: String, url: URL)] {
        var locs: [(name: String, icon: String, url: URL)] = []
        let fm = FileManager.default
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            locs.append(("Desktop", "menubar.dock.rectangle", desktop))
        }
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            locs.append(("Downloads", "arrow.down.circle", downloads))
        }
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            locs.append(("Documents", "doc.text", docs))
        }
        return locs
    }

    private var customFolderLocation: URL? {
        guard let folder = library.customFolder else { return nil }
        let isQuick = quickLocations.contains { $0.url.path == folder.path }
        return isQuick ? nil : folder
    }

    private func locationRow(name: String, icon: String, url: URL) -> some View {
        let isSelected = library.folder?.path == url.path
        return Button {
            library.selectLocation(url)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 17).foregroundStyle(isSelected ? Color.blue : muted)
                Text(name).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 11).frame(height: 30)
            .background(isSelected ? Color.blue.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) folder")
        .accessibilityValue(isSelected ? "Selected location" : "Not selected")
        .accessibilityHint("Scans this folder")
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(muted)
                TextField("Search files, or try “pdfs from last week”", text: $library.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search files")
                    .accessibilityHint("Search by name, type, date, size, or location")
                    .onKeyPress(.downArrow) {
                        guard !library.visible.isEmpty else { return .ignored }
                        showSearchSuggestions = false
                        isSearchFocused = false
                        isResultsFocused = true
                        moveSelection(delta: 1)
                        return .handled
                    }
                    .onSubmit {
                        if !library.query.isEmpty {
                            library.addRecentSearch(library.query)
                            showSearchSuggestions = false
                        }
                    }
                if !library.query.isEmpty {
                    Button {
                        library.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(muted)
                    .accessibilityLabel("Clear search")
                }
                Button {
                    showSearchSuggestions.toggle()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(showSearchSuggestions ? Color.blue : muted)
                }
                .buttonStyle(.plain)
                .help("Search suggestions & recent searches")
                .accessibilityLabel("Search suggestions and recent searches")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 13).frame(width: 440, height: 37)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSearchFocused ? Color.blue.opacity(0.55) : Color.black.opacity(0.18)))
            .popover(isPresented: $showSearchSuggestions, arrowEdge: .bottom) {
                SearchSuggestionsView(library: library) { selectedQuery in
                    library.query = selectedQuery
                    library.addRecentSearch(selectedQuery)
                    showSearchSuggestions = false
                }
            }
            .onChange(of: isSearchFocused) { _, focused in
                if focused && library.query.isEmpty {
                    showSearchSuggestions = true
                }
            }
            Spacer()
            Text("Library size  \(bytes(library.summary(for: "Home").bytes))")
                .font(.caption).foregroundStyle(muted)
            if let folder = library.folder {
                Button { library.scan(folder) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(muted).help("Refresh library")
                    .accessibilityLabel("Refresh library")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if library.inspectedItem == nil && !library.files.isEmpty {
                        library.inspectedItem = library.files.first
                    }
                    showInspector.toggle()
                }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .foregroundStyle(showInspector && library.inspectedItem != nil ? Color.blue : muted)
            }
            .buttonStyle(.plain)
            .help("Toggle file details inspector")
            .accessibilityLabel("Toggle file details inspector")
        }
        .padding(.horizontal, 30).frame(height: 67)
    }

    private func bannerView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            Text(message).font(.system(size: 13, weight: .medium))
            Spacer()
            if library.canUndoTrash {
                Button {
                    library.undoLastTrash()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Button {
                // Dismissing only hides the message; ⌘Z can still undo.
                library.bannerMessage = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(Color.blue.opacity(0.08))
    }

    private var selectionBottomBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)
            Text("\(library.selectedIDs.count) items selected (\(bytes(library.selectedBytes)))")
                .font(.system(size: 13, weight: .medium))

            Button("Deselect") {
                library.deselectAll()
            }
            .buttonStyle(.link)
            .font(.caption)

            Button("Select All Visible") {
                library.selectAllVisible()
            }
            .buttonStyle(.link)
            .font(.caption)

            Spacer()

            if library.category == "Duplicates" {
                Button {
                    library.selectDuplicateCopies()
                } label: {
                    Label("Auto-select Copies", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(role: .destructive) {
                showTrashConfirmation = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(white: 0.965))
        .overlay(Divider(), alignment: .top)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting).font(.system(size: 29, weight: .medium))
                    Text("\(library.files.count.formatted()) files · \(bytes(library.summary(for: "Home").bytes)) across your library")
                        .font(.caption).foregroundStyle(muted)
                }
                Spacer()
                if let folder = library.folder {
                    Button { library.scan(folder) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            if library.folder == nil {
                VStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 35)).foregroundStyle(.blue)
                    Text("Your files, in one place").font(.title3.weight(.semibold))
                    Text("Choose a folder to explore its files and cleanup suggestions.")
                        .foregroundStyle(muted)
                    Button("Choose Folder") { library.chooseFolder() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 340)
                .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
            } else if !library.scanning && library.files.isEmpty && scanNoticeTitle != nil {
                scanNotice
                    .frame(maxWidth: .infinity, minHeight: 340)
            } else {
                if !library.scanning && scanNoticeTitle != nil {
                    scanNotice
                }
                VStack(alignment: .leading, spacing: 16) {
                    heading("Library", "6")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(categories, id: \.self) { folderCard($0) }
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        heading("Clean Up")
                        Spacer()
                        Button("See all →") { library.category = "Clean Up" }.buttonStyle(.plain)
                            .font(.caption).foregroundStyle(muted)
                            .accessibilityLabel("See all cleanup suggestions")
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        cleanupCard("Duplicates", "square.on.square", .red)
                        cleanupCard("Forgotten Downloads", "arrow.down.circle", .blue)
                        cleanupCard("Old Screenshots", "camera.viewfinder", .pink)
                        cleanupCard("Large Files", "externaldrive", .green)
                    }
                }
                downloadedFromSection
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        heading("Recent Files", library.summary(for: "Recents").count.formatted())
                        Spacer()
                        Button("See all →") { library.category = "Recents" }.buttonStyle(.plain)
                            .font(.caption).foregroundStyle(muted)
                            .accessibilityLabel("See all recent files")
                    }
                    if library.files.isEmpty {
                        Text(library.scanning ? "Indexing your files…" : "No files found")
                            .font(.caption).foregroundStyle(muted)
                    } else {
                        fileList(Array(library.files.prefix(5)))
                    }
                }
            }
        }
    }

    private var scanNoticeTitle: String? {
        if library.status == "Scan cancelled" { return "Scan cancelled" }
        if library.indexUnavailable { return "Index unavailable" }
        if library.status.contains("unavailable") { return "Folder unavailable" }
        return nil
    }

    private var scanNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: library.status == "Scan cancelled" ? "pause.circle" : "folder.badge.questionmark")
                .font(.system(size: 27))
                .foregroundStyle(.orange)
            Text(scanNoticeTitle ?? "Scan stopped")
                .font(.title3.weight(.semibold))
            Text(library.indexUnavailable ? "Filewise could not save the index. Use Rebuild Index in the sidebar, or open its folder to keep a copy for recovery." : library.status == "Scan cancelled"
                 ? (library.files.isEmpty ? "This folder has not been indexed yet. Restart the scan to see its files." : "The scan stopped. Previous results are still available below.")
                 : (library.files.isEmpty ? "Filewise could not read this folder. Check its permissions, reconnect its drive, or choose another folder." : "Filewise could not read this folder or all of its files. Check permissions or reconnect its drive. Previous results are still available below."))
                .font(.subheadline)
                .foregroundStyle(muted)
            HStack(spacing: 10) {
                if let folder = library.folder {
                    Button("Try Again") { library.scan(folder) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Choose Folder") { library.chooseFolder() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
    }

    private func folderCard(_ title: String) -> some View {
        let summary = library.summary(for: title)
        return Button { library.category = title } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: icon(title)).font(.system(size: 23))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10))
                }
                .foregroundStyle(.black.opacity(0.55))
                Spacer(minLength: 25)
                Text(title).font(.system(size: 16, weight: .medium))
                Divider().padding(.vertical, 11)
                HStack {
                    Text("\(summary.count.formatted()) items")
                    Spacer()
                    Text(bytes(summary.bytes))
                }.font(.system(size: 11)).foregroundStyle(muted)
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: 160)
            .background(categoryColor(title), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
        .accessibilityLabel("\(title), \(summary.count.formatted()) items")
        .accessibilityHint("Shows files in this category")
    }

    private func cleanupCard(_ title: String, _ symbol: String, _ color: Color) -> some View {
        let summary = library.summary(for: title)
        return Button { library.category = title } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol).font(.system(size: 19))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.65), in: Circle())
                Spacer(minLength: 17)
                Text(title).font(.system(size: 12)).foregroundStyle(muted).lineLimit(1)
                HStack(alignment: .firstTextBaseline) {
                    Text(bytes(summary.bytes)).font(.system(size: 23, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text("\(summary.count.formatted()) files ›").font(.system(size: 10))
                        .foregroundStyle(muted).lineLimit(1)
                }
            }
            .padding(17).frame(maxWidth: .infinity, minHeight: 145)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
        .accessibilityLabel("\(title), \(summary.count.formatted()) files, \(bytes(summary.bytes))")
        .accessibilityHint("Review cleanup candidates")
    }

    private var downloadedFromSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                heading("Downloaded From", library.downloadSources.isEmpty ? nil : "\(library.downloadSources.count)")
                Spacer()
                if !library.downloadSources.isEmpty {
                    Button("See all →") {
                        library.category = "Downloaded From"
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .accessibilityLabel("See all download origins")
                }
            }

            if library.downloadSources.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(muted)
                    Text("No file download origins detected in this folder.")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(library.topDownloadSources.prefix(8), id: \.key) { source, summary in
                            downloadSourceCard(source: source, summary: summary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func downloadSourceCard(source: String, summary: LibrarySummary) -> some View {
        Button {
            library.category = "Origin: \(source)"
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(originColor(source).opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: originIcon(source))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(originColor(source))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(source)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(summary.count.formatted()) files · \(bytes(summary.bytes))")
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minWidth: 170, alignment: .leading)
            .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func originIcon(_ source: String) -> String {
        switch source.lowercased() {
        case "canva": return "paintbrush.pointed"
        case "chatgpt": return "bubble.left.and.text.bubble.right"
        case "x", "twitter": return "message"
        case "github", "gitlab": return "chevron.left.forwardslash.chevron.right"
        case "pinterest": return "pin"
        case "figma": return "square.on.circle"
        case "google", "google chrome": return "globe"
        case "safari": return "safari"
        case "slack": return "number"
        case "discord": return "bubble.left"
        case "telegram": return "paperplane"
        case "youtube": return "play.rectangle"
        case "numbers": return "tablecells"
        case "pages": return "doc.text"
        case "keynote": return "play.display"
        case "whatsapp": return "phone.bubble.left"
        default: return "arrow.down.circle"
        }
    }

    private func originColor(_ source: String) -> Color {
        switch source.lowercased() {
        case "canva": return .teal
        case "chatgpt": return .green
        case "numbers": return .green
        case "pages": return .orange
        case "keynote": return .blue
        case "whatsapp": return .green
        case "x", "twitter": return .black
        case "github": return .purple
        case "pinterest": return .red
        case "figma": return .orange
        case "google", "google chrome": return .blue
        case "safari": return .blue
        case "slack": return .indigo
        default: return .blue
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.query.isEmpty ? library.category : "Search Results")
                        .font(.system(size: 29, weight: .medium))
                    Text("\(library.visible.count.formatted()) files")
                        .font(.caption).foregroundStyle(muted)
                }
                Spacer()
                if library.category == "Duplicates" && !library.visible.isEmpty {
                    Button {
                        library.selectDuplicateCopies()
                    } label: {
                        Label("Select Duplicate Copies", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("← Home") { library.category = "Home"; library.query = "" }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(muted)
            }
            if library.visible.isEmpty && library.files.isEmpty && !library.scanning && scanNoticeTitle != nil {
                scanNotice
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if library.visible.isEmpty {
                ContentUnavailableView("No matching files", systemImage: "magnifyingglass",
                    description: Text(library.scanning ? "Indexing your files…" : "Try another search or category."))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                fileList(library.visible)
            }
        }
    }

    private func fileList(_ items: [FileItem]) -> some View {
        let displayItems = items.prefix(300)
        return VStack(spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(displayItems) { item in
                    let isSelected = library.selectedIDs.contains(item.id)
                    let isInspected = library.inspectedItem?.id == item.id

                    HStack(spacing: 12) {
                        Button {
                            library.toggleSelection(for: item)
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(isSelected ? Color.blue : muted.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSelected ? "Deselect \(item.name)" : "Select \(item.name)")
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")

                        Image(nsImage: IconCache.shared.icon(for: item))
                            .resizable().frame(width: 29, height: 29)

                        Button {
                            library.inspectedItem = item
                            showInspector = true
                            isResultsFocused = true
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(item.url.deletingLastPathComponent().path)
                                    .font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inspect \(item.name)")
                        .accessibilityHint("Shows file details")
                        Spacer()
                        if item.duplicate {
                            Image(systemName: "square.on.square")
                                .foregroundStyle(.orange)
                                .help("Duplicate file")
                        }
                        Text(item.displaySize).font(.caption).foregroundStyle(muted)
                            .frame(width: 80, alignment: .trailing)
                        Text(item.modified, style: .date).font(.caption).foregroundStyle(muted)
                            .frame(width: 85, alignment: .trailing)

                        Button {
                            library.previewURL = item.url
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(muted)
                        }
                        .buttonStyle(.plain)
                        .help("Quick Look")
                        .accessibilityLabel("Quick Look \(item.name)")
                    }
                    .padding(.horizontal, 15).frame(height: 58)
                    .background(isInspected ? Color.blue.opacity(0.06) : (isSelected ? Color.blue.opacity(0.03) : Color.clear))
                    .contentShape(Rectangle())
                    .id(item.id)
                    .onTapGesture {
                        library.inspectedItem = item
                        showInspector = true
                        isResultsFocused = true
                    }
                    .onTapGesture(count: 2) {
                        NSWorkspace.shared.open(item.url)
                    }
                    .contextMenu {
                        Button("Quick Look") { library.previewURL = item.url }
                        Button("Inspect Details") {
                            library.inspectedItem = item
                            showInspector = true
                        }
                        Divider()
                        Button("Open") { NSWorkspace.shared.open(item.url) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        Divider()
                        Button("Move to Trash", role: .destructive) {
                            singleItemToTrash = item
                            showSingleTrashConfirmation = true
                        }
                    }
                    Divider().padding(.leading, 55)
                }
            }
            if items.count > 300 {
                Text("Showing first 300 of \(items.count.formatted()) files. Narrow your search to see more.")
                    .font(.caption).foregroundStyle(muted)
                    .padding(.vertical, 16)
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.07)))
    }

    private var currentNavigableFiles: [FileItem] {
        if library.category == "Home" && library.query.isEmpty {
            return Array(library.files.prefix(5))
        } else {
            return Array(library.visible.prefix(300))
        }
    }

    private func moveSelection(delta: Int) {
        let items = currentNavigableFiles
        guard !items.isEmpty else { return }

        let targetIndex: Int
        if let inspected = library.inspectedItem,
           let currentIndex = items.firstIndex(where: { $0.id == inspected.id }) {
            targetIndex = max(0, min(items.count - 1, currentIndex + delta))
        } else {
            targetIndex = delta > 0 ? 0 : items.count - 1
        }

        let newItem = items[targetIndex]
        library.inspectedItem = newItem
        showInspector = true
        if library.previewURL != nil {
            library.previewURL = newItem.url
        }
    }

    private func heading(_ title: String, _ count: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 20, weight: .medium))
            if let count {
                Text(count).font(.caption).foregroundStyle(muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.black.opacity(0.04), in: Capsule())
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func bytes(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func icon(_ title: String) -> String {
        switch title {
        case "Images": "photo"
        case "Videos": "play.rectangle"
        case "Music": "music.note"
        case "Documents": "doc.text"
        case "Archives": "archivebox"
        case "Apps": "square.grid.2x2"
        default: "doc"
        }
    }

    private func categoryColor(_ title: String) -> Color {
        switch title {
        case "Images": Color(red: 0.92, green: 0.92, blue: 1)
        case "Videos": Color(red: 0.90, green: 0.94, blue: 1)
        case "Music": Color(red: 1, green: 0.94, blue: 0.91)
        case "Documents": Color(red: 0.90, green: 0.96, blue: 0.94)
        case "Archives": Color(red: 1, green: 0.96, blue: 0.86)
        default: Color(red: 1, green: 0.92, blue: 0.95)
        }
    }
}
