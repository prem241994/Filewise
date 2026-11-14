# Filewise Roadmap

Filewise is a native macOS information finder. The product should give users one calm search surface for files and useful information stored across their Mac, while making cleanup suggestions understandable and reversible.

## Product direction

The main interaction is a single search field that accepts both ordinary terms and natural requests such as `PDFs from last week`, `screenshots in Downloads`, or `large videos`. Results should explain why each item matched, show its source location, and provide a clear next action.

The first release should prioritize speed, trust, and clarity. It should ask for access only when needed, explain what it found, and avoid destructive actions without an explicit user choice.

## Recommended technology stack

### Application

- **Swift 6** for the macOS application
- **SwiftUI** for the main interface, navigation, search surface, cards, lists, and settings
- **AppKit** for Finder integration, menu bar behavior, global hotkeys, Quick Look, open panels, and other macOS-specific interactions
- **Swift Package Manager** for project and dependency management

### Local indexing and search

- **FileManager** and **URL resource values** for filesystem scanning and metadata
- **FSEvents** or `DispatchSource` for observing changes after an initial scan
- **SQLite** through **GRDB.swift** or a small Core Data model for the local index
- **SQLite FTS5** for fast full-text filename and path search
- **CryptoKit SHA-256** for duplicate detection after size-based grouping
- **NSMetadataQuery** only where Spotlight metadata provides a useful supplement

### Natural-language search

- Start with a local rule-based query parser for dates, file types, folders, sizes, and keywords
- Add an optional **Foundation Models** integration when the deployment target supports it and local language understanding improves the experience
- Keep the parser’s output structured so every result can show the interpreted filters

### Privacy and macOS integration

- Security-scoped bookmarks for user-selected folders
- App Sandbox entitlements for distribution through the Mac App Store or a hardened signed build
- Keychain only for credentials if external integrations are added later
- No cloud service in the first release. The index and search should remain on the Mac

### Development and delivery

- **VS Code** for editing, terminal work, Git, and project documentation
- **Xcode Command Line Tools** for local builds
- **Xcode** later for signing, capabilities, entitlements, Instruments, and notarization
- **GitHub Actions** for build and archive checks after the first working prototype
- `.app` and `.dmg` packaging for internal distribution, followed by Developer ID signing and notarization

## UX principles

1. One primary search entry point. The user should not need to understand the index.
2. Progressive detail. Show a useful result first, then expose path, metadata, and match reasons on demand.
3. Plain language. Use labels such as “Found in Downloads” and “Identical copy” instead of internal terminology.
4. Safe actions. Open, reveal, preview, and move to Trash should be obvious and separate.
5. Visible state. Scanning, permissions, stale indexes, and empty results need clear explanations.
6. Keyboard friendly. The search field, result navigation, preview, and Finder reveal should all work without a mouse.

## Roadmap

### Phase 0 — Product foundation

- Confirm the first-release scope and minimum supported macOS version
- Create the Swift Package or Xcode project structure
- Establish Filewise colors, typography, iconography, and spacing tokens
- Create sample data so UI work does not wait for the scanner

### Phase 1 — Intuitive shell

- Build the main window with a prominent search field
- Add sidebar sections for All Files, Recent, Duplicates, Screenshots, Downloads, and Large Files
- Add result rows with file icon, name, location, date, size, and match explanation
- Add empty, loading, permission, and error states
- Add keyboard navigation and Finder actions

### Phase 2 — Real local index

- Implement folder selection and security-scoped bookmarks
- Scan metadata asynchronously with cancellation and progress
- Persist the file index locally
- Add incremental updates from filesystem events
- Add index health and last-scanned status

### Phase 3 — Search and discovery

- Add filename, extension, path, date, size, and folder filters
- Add rule-based natural-language parsing
- Add search suggestions and recent searches
- Add previews and a detail inspector
- Measure search latency on realistic folders

### Phase 4 — Cleanup intelligence

- Detect duplicates using size grouping and SHA-256 hashes
- Add old screenshot, large file, and forgotten download views
- Explain each cleanup recommendation
- Add multi-select and move-to-Trash with confirmation
- Add undo and recovery guidance

### Phase 5 — Mac-native workflow

- Add a menu bar entry
- Add a configurable global shortcut
- Add drag-and-drop folders and files
- Add Quick Look integration
- Add launch-at-login as an opt-in setting

### Phase 6 — Release hardening

- Add accessibility labels and VoiceOver checks
- Test permission changes, disconnected volumes, aliases, packages, and large indexes
- Profile memory and scan performance with Instruments
- Add crash logging that does not include file contents or paths by default
- Sign, notarize, package, and prepare release documentation

## Definition of done for v1

- A user can select a folder and understand the current scan state
- A user can search by ordinary terms and supported natural-language filters
- Results are fast, readable, explainable, and keyboard accessible
- Duplicate and cleanup suggestions are evidence-based
- Destructive actions require an explicit user action and support recovery
- The app works offline and keeps indexed data local
