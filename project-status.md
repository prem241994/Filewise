# Filewise Project Status

Last updated: 2026-11-19

## Current phase

Phase 2 — Local scanning, search, and dashboard

## Overall status

**Working local prototype with a saved index and dashboard.** Filewise builds and launches, stores file metadata in SQLite, and refreshes when files change in the selected folder.

## Completed

- Reviewed the supplied demo video
- Identified the core product pattern as a Mac file and information finder
- Chosen the project name **Filewise**
- Created a first SwiftUI prototype with folder scanning, file search, duplicate detection, and cleanup categories
- Confirmed that the prototype source compiles against the installed macOS SDK
- Defined the recommended technology stack and phased roadmap
- Created a Swift package layout, VS Code build tasks, a direct compiler build script, and a README
- Renamed the app and window to Filewise
- Added Recent and Large Files views, clearer empty states, result dates, and broader query parsing
- Prevented an older scan from replacing the results of a newer scan
- Built and launched `/Users/premkumar/Desktop/Filewise/.build/Filewise.app` successfully
- Verified a four-file test folder in the app, including two identical PDFs and an old screenshot
- Verified `screenshots in Downloads` and `pdf` searches, the Duplicates view, and Finder reveal
- Added a saved folder bookmark, automatic rescan on launch, scan progress count, and cancellation
- Verified that the selected test folder restored and rescanned after an app restart
- Added a SQLite index in Application Support with transactional replacement of a completed scan
- Added recursive file-change monitoring and a short debounce before refreshing
- Verified that adding and removing a file in a nested folder updated the app and index automatically
- Verified that the app relaunched with the selected folder and indexed results
- Split the prototype into Models, Services, ViewModels, and Views source folders
- Rebuilt the window around the supplied reference: left navigation, one search field, six library cards, four cleanup cards, and recent files
- Connected card and sidebar counts to indexed data; category cards open filtered file lists
- Added change timestamps and SHA-256 hashes to the index, with migration from the older schema
- Reused hashes for unchanged files and updated only changed or removed SQLite rows
- Verified unchanged duplicate PDFs kept their SQLite row IDs on refresh
- Verified the Desktop build and category navigation in the running Mac app
- Added SQLite FTS5 full-text search index for filename, extension, and path queries with automatic prefix matching
- Resolved main-thread sluggishness: debounced background search (60ms), in-memory IconCache avoiding sync filesystem calls, schema initialization caching, and removing AnyView type erasure
- Added interactive cleanup & multi-select: selection bar, auto-select duplicate copies (keeps original, marks copies), and Move-to-Trash with confirmation sheets showing selected file size
- Added background asynchronous trash execution with a progress dialog (percentage bar, file counter, currently moved file, size moved to Trash, and Cancel button)
- Enhanced progress dialog with complete state: transitions to green checkmark, 100% filled bar, total space summary, and prominent 'Done' button upon completion
- Optimized bulk FTS cleanup from 6 seconds down to 0.02s (single set deletion instead of 20,000 unindexed virtual-table scans) and replaced native ProgressView with solid custom bar to prevent 100% flicker
- Fixed screenshot classification: strictly requires an image file extension (PNG, JPG, HEIC, TIFF, etc.) so code files (e.g. .ts, .mjs, .py) with 'screenshot' in their name are never falsely classified as screenshots
- Added 'Downloaded From' origin attribution: extracts source domains and apps via macOS extended attributes (kMDItemWhereFroms & quarantine), displays origin cards on the dashboard (matching reference UI), persists origin in SQLite, and enables one-click filtering by download origin
- Added Search Filter Suggestions & Recent Searches Popover: interactive filter pills (PDFs from last week, Recent Screenshots, Large files, etc.), persistent recent searches history in UserDefaults with clear action, and auto-popover on search bar focus
- Added Quick Look preview integration (Spacebar / preview eye button) and collapsible File Detail Inspector panel with file metadata, location, and quick actions
- Added instantaneous SQLite & FTS removal (`FileIndex.removePaths`) on trashing files without requiring full directory rescans
- Added In-App Trash Undo/Restore: persistent `trash_manifest` table in SQLite tracking original and Trash file locations; one-click "Undo" banner action and `⌘Z` shortcut to safely restore files back from macOS Trash to their original locations
- Added Quick Locations in Sidebar: one-click access to Desktop, Downloads, Documents, and custom folders with active location indicator
- Added Full Mac-Native Keyboard Navigation & Shortcuts: Up/Down arrow navigation across files with auto-scrolling via `ScrollViewReader`, live Quick Look preview update on navigation, Space to toggle Quick Look, Return to open, Delete/Backspace to prompt trash, ⌘F to jump to search, ⌘A to select all visible files, and Esc to dismiss/deselect
- Fixed partial Trash cancellation: every file already moved is recorded and removed from the index, and Undo remains available
- Replaced "space freed" claims with "size moved to Trash" because disk space is not reclaimed until Trash is emptied
- Added a repeatable temporary-folder integration test for partial cancellation, index consistency, and Undo restoration
- Added a 3,000-file integration check for scan cancellation, full rescans, FTS search, and missing/restricted folders
- Scoped FTS matches to the active folder and handled macOS paths that appear under both `/var` and `/private/var`
- Isolated integration-test SQLite databases from the user's Filewise index
- Verified scan progress and cancellation in the running app with temporary large-folder fixtures; cancellation leaves no partial results
- Verified the permission-failure state in the running app and added prominent retry/choose-folder guidance for canceled or unavailable scans
- Corrected scan status text so it only claims saved results when the selected folder has cached files
- Recognized "video" and "videos" as file-type filters, so searches such as "large videos" no longer treat them as filename words
- Verified "pdfs from last week", "large videos", and "large files" against dated and sized files in a real scan using the isolated integration database
- Added descriptive accessibility labels to search controls, file selection and inspection actions, Quick Look buttons, and the inspector close button
- Added keyboard focus for results so Down Arrow from search selects the first file; verified Up/Down navigation and Space preview in the running app

- Made index schema initialization transactional and checked SQLite errors; failed initialization can be retried without replacing the database
- Added isolated checks for older-schema migration, preservation of Trash Undo records, and non-destructive corrupt-database handling
- Added the completion time to the current successful scan status and report initialization errors when the index is unavailable

- Added persistent per-folder last-successful-scan timestamps and a transactional rebuild of derived index data that preserves Trash Undo records
- Added an isolated scan benchmark; a 10,000-file unique-size fixture measured 0.94 s initial scan, 0.92 s unchanged refresh, and 150.4 MiB peak process RSS on this machine (including the fixture setup)

- Journal Trash moves individually before and after moving; stop on write failure, attempt immediate rollback, and recover the latest recorded batch on reopening a folder
- Add read-only export of accessible Undo records and isolated checks for write failures, partial cancellation, restart, and rollback

- Modernized the window: native split view sidebar with counts, toolbar search, a resizable inspector, and system light/dark appearance support
- Replaced the 300-row custom list with a sortable native table (name, cleanup notes, size, modified) with multi-select, Return to open, Delete to trash, and context menus
- Added cleanup explanations: reason tags in results, a "Why it's suggested" inspector section, and a list of identical copies for duplicates
- Showed locations relative to the selected folder instead of full system paths, and corrected singular/plural counts
- Trash confirmations now name the files being moved; added File, Edit, and View menu commands
- Added shared design tokens (`Views/Theme.swift`) and a light/dark UI snapshot script

- Split the code into two modules: `FilewiseCore` (model, index, scanning, search, Trash, and watcher, with no UI) and the SwiftUI app
- Moved scanning, search, and Trash/Undo out of the view model into `FolderScanner`, `FileSearch`, and `TrashService`; their safety steps and messages are unchanged
- Adopted the Swift 6 language mode with complete data-race checking: the view model, navigation state, and icon cache run on the main actor; background work uses tasks with Sendable values; cancellation tokens use a system lock
- Shared build settings in `scripts/common.sh`; all checks pass, and the 10,000-file benchmark is unchanged when old and new builds run back to back (0.37 s initial scan and refresh)

- Moved ⌘F (Search Files) and ⌘Z (restore the last Trash batch, or undo typing in the search field) into menu commands, and focus the toolbar search field directly; both were previously swallowed by the standard Edit menu
- Added Quick Look thumbnails for photos, videos, and documents in lists, Home, and the inspector; a gallery grid for Images, Videos, and Screenshots with a List/Grid switch per view; and a Recent Photos & Videos strip on Home
- The inspector plays videos (▶ on a tile starts playback) and shows scrollable document previews, all through on-device Quick Look
- Redesigned the Home Library and Clean Up cards with preview stacks, size-share bars, and hover feedback
- "By Source" now counts the same files its page lists
- "Select Extra Copies" offers keep rules: oldest, newest, shortest name, or the copy in a chosen folder (remembered; covered by `scripts/test-duplicates.sh`)
- Old downloads now use the later of the modification date and the last-opened date macOS records on each file (`com.apple.lastuseddate#PS`); the inspector shows Last Opened. This adds about 0.05 s per 10,000 files to a scan

## Current limitations

- If the database itself is unreadable, automated salvage is not yet implemented; the original database is left intact for manual recovery
- Natural-language parsing is currently limited to simple rules
- The installed Swift Package Manager crashes before compilation because its libraries are mismatched. `scripts/build.sh` compiles the app directly with the installed Swift compiler
- Each background refresh still enumerates the full selected folder; unchanged duplicate hashes are reused when change metadata matches
- File-change monitoring only runs while the app is open. A background refresh on launch catches changes made while it was closed
- The menu bar provides Open Filewise and Search Files actions; a configurable global shortcut is not yet implemented
- App bundle sizes sum regular files within the bundle; unreadable bundles show an unavailable size and are excluded from size-based suggestions
- Cleanup cards show review candidates and their total size, not guaranteed recoverable space
- A full spoken VoiceOver pass and visual focus-ring review still remain before release; keyboard behaviour of the new table (Space for Quick Look, Delete, Return) should be checked by hand
- The local ZIP package is ad-hoc signed; Developer ID signing and notarization remain necessary for distribution
- The build and test scripts use the active SDK by default; this Mac currently needs `FILEWISE_SDK_PATH` set to its compatible macOS 26 SDK because its active SDK and Swift compiler are mismatched
- A GitHub Actions workflow is present locally for building and running the isolated index, search, and Trash safety checks; its first hosted run is pending a push

The 10,000-file metadata benchmark on 14 November 2026 measured 0.92 s for the initial scan, 0.83 s for an unchanged refresh, and 154.0 MiB peak process RSS. This fixture does not measure duplicate hashing.

## Next milestone

Harden indexing on large or changing folders. Search date, type, and size phrases pass the isolated scan integration check; keyboard result navigation and primary accessibility labels are verified in the running app. Broader UI checks remain for suggestions, recent searches, and the detail inspector.

## Next actions

- Review the current macOS 14 minimum target before distribution
- Repair or replace the mismatched Swift Package Manager installation when convenient
- Extend recovery options for unreadable index databases
- Complete a spoken VoiceOver pass on results, sidebar, cleanup controls, and dialogs
- Profile large-folder rescans and reduce repeated metadata work

## Risks and decisions

- Broad “all information on the Mac” search needs a clear first-release boundary. File metadata and user-selected folders are the initial boundary.
- Access to protected locations may require user permission and careful security-scoped bookmark handling.
- Full content search can be expensive and privacy-sensitive, so it should be evaluated after metadata search is reliable.
- Foundation Models support and minimum OS compatibility should be decided before adding an on-device language model dependency.

## Verification checklist

- [x] Project builds with the same `scripts/build.sh` command configured in VS Code
- [x] App opens as a normal macOS application
- [x] Folder selection works
- [x] Scan cancellation preserves the index during a 3,000-file integration test
- [x] Scan progress and cancellation UI work during a long scan
- [x] Search returns correct results for filename, file type, and location in the test folder
- [x] Search date and size phrases return the expected files after a real scan in the isolated integration check
- [x] Dashboard library cards and category navigation work in the running Mac app
- [x] Duplicate detection identifies identical content
- [x] Finder reveal works
- [x] Partial Trash cancellation keeps the index and Undo consistent in a temporary-folder integration test
- [x] Missing and restricted folders do not replace saved results with an empty index
- [x] Primary accessibility labels and keyboard result navigation are checked in the running app
- [ ] No file contents leave the Mac by default
