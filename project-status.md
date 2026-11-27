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
- Added a Settings window (⌘,): large-file size, the age after which screenshots and downloads are old, and ignored folders that scans and the folder watcher skip. Limits apply immediately; changing ignored folders rescans
- Enabled the App Sandbox (user-selected folders read-write, security-scoped bookmarks, Downloads; no network). Chosen folders reopen after relaunch through bookmarks, the selected folder's access is held while it is selected, and Desktop/Documents ask for access once from the sidebar. Verified with a sandboxed probe that Trash Undo restores from `~/.Trash` both in the same launch and after a relaunch. `package.sh` fails if the sandbox entitlement is lost or a network entitlement appears
- Added a first-run welcome page on Home: what Filewise does, Trash with Undo, privacy, a one-click Scan Downloads (no permission prompt in the sandbox), and Choose Another Folder. The inspector stays hidden until a folder is chosen. `snapshot-ui.sh` captures it as the `welcome` step
- Added the 7-day free trial and one-time unlock (StoreKit 2, no server): the trial starts at the App Store's original download date, Move to Trash and Select Extra Copies show an unlock sheet after it ends (naming the size being cleaned), and search, browsing, suggestions, and Undo stay free. When the trial has ended, the unlock sheet appears by itself once per launch, after the scan and naming the size of the suggestions; during the trial the sidebar shows the days left. Settings shows the status (with Restore Purchase), and Filewise → Unlock Filewise… opens the sheet. Covered by `scripts/test-license.sh`; a development-only override previews each state. Needs the `app.filewise.desktop.unlock` non-consumable in App Store Connect before real purchases can be tested
- Made the trial follow App Review Guideline 3.1.1: it starts when the user taps Start Free Trial (a free non-consumable named "7-day Trial", `app.filewise.desktop.trial`), not silently at download, and the welcome page, sidebar, and unlock sheet show its length, what it gates, and the price first. Before the trial starts, cleanup actions offer it. Development builds outside the App Store keep the trial locally
- Added the app icon: a friendly orange owl (the "wise" in Filewise) wearing round indigo glasses, with sparkles, on an indigo rounded square with the welcome page's pink and teal glows. Drawn in code (`tools/AppIcon.swift`, rendered by `scripts/make-icon.sh`) and checked as macOS 26 presents it (not placed in a gray plate) and at 64 px
- VoiceOver pass: checked what VoiceOver reaches on the welcome page, Home, results list and gallery, unlock sheet, and Settings with a new snapshot `Accessibility` step that dumps the accessibility tree. Page and section titles are now headings, decorative icons are hidden, cleanup tags read as text, file tiles and rows offer Open, Quick Look, Show in Finder, and Move to Trash actions, and scan results, banners (with Undo), and finished Trash moves are announced. A spoken pass with VoiceOver by a person is still worthwhile
- Space ring on Home: a ring chart of the folder's size by Library category (plus "Other"), with a legend whose rows open each category and highlight their slice on hover, and a bar for the disk the folder is on (this folder, everything else, free). Disk capacity comes from the folder's volume resource values, so it works in the sandbox. Labeled for VoiceOver
- Motion pass: files moved to Trash shrink and fade out of the gallery and slide out of lists, and come back the same way on Undo; counts, sizes, and the space ring roll to their new values after Trash, Undo, and scans; the Undo banner slides in from the top; Home's sections rise in one after another the first time a folder is shown; the Refresh icon pulses while scanning and the search sparkle bounces. One shared spring (`Motion` in ViewModels) drives it, and all of it is off with Reduce Motion
- Cleanup confidence: each cleanup reason has a `CleanupConfidence` (Core). Home groups the cleanup cards under "Usually safe to clear" (Duplicates, Old Downloads, Old Screenshots) and "Your call" (Large Files), and the inspector adds one line of advice per reason, such as keeping one copy of a duplicate
- Tester build: `scripts/beta.sh` makes `.build/Filewise-Beta.zip`, a universal (Apple silicon and Intel), sandboxed, ad-hoc-signed copy with everything unlocked (`FILEWISE_BETA`) and a "How to open" note for testers. The script checks the signature, the sandbox and no-network entitlements, and that the license-testing override isn't present; Settings shows "Beta version" in the Purchase section
- Smarter dates and empty searches: "last week" now runs from the start of the previous week up to now (it used to be only the previous calendar week, so Monday's files were missed on a Wednesday), and searches also understand today, yesterday, this week, this month, and last month. An empty search explains itself: a dated one names the range searched and the date of the newest match without the date, with Search All Dates and Choose Another Folder buttons. Covered by the new `test-search-dates.sh` (in CI) and `test-scan-search.sh`
- Search words inside screenshots: after each scan, the text in new or changed screenshots is read on the device with Vision (about 0.6 s each on an Apple silicon Mac), stored in the index with its own FTS5 table, and matched by search together with names; stored text is reused for unchanged screenshots and dropped for removed ones. The sidebar shows "Reading text in screenshots… n of N", and the inspector shows the text. Covered by `test-image-text.sh` (in CI)
- Faster refreshes: file dates are now rounded the way the index stores them, so unchanged files no longer look changed after a reload (about half of real files did). Unchanged 10k-file refresh went from 0.44–0.47 s to 0.29 s; `test-scan-search.sh` checks the round trip
- Home fits narrow windows without squeezing the sidebar: the space ring card and Clean Up section report a small ideal width (as Recent Files already did), the ring's legend moves below the ring, cleanup cards stack, and Recent Files rows drop the tags and then the size so names stay readable. Checked with snapshots at 860 and 1100 points (`FILEWISE_SNAPSHOT_WIDTH`, and new `scroll2`/`end` snapshot actions)
- Fixed: Trash moves in a folder reached through a symlink (such as /var for /private/var) were reported as "Undo records could not be saved" and offered no Undo, although the records were saved, because `latestTrashBatch` and `hasUnresolvedTrashMove` matched only one form of the folder's path. The folder keep rule had the same flaw. All three now use `PathPrefixes`, which also covers the /private-stripped form. Found while capturing marketing screenshots; `test-trash-safety.sh` and `test-duplicates.sh` cover symlinked folders and fail on the old code

## Current limitations

- If the database itself is unreadable, automated salvage is not yet implemented; the original database is left intact for manual recovery
- Natural-language parsing is currently limited to simple rules
- The installed Swift Package Manager crashes before compilation because its libraries are mismatched. `scripts/build.sh` compiles the app directly with the installed Swift compiler
- Each background refresh still enumerates the full selected folder; unchanged duplicate hashes are reused when change metadata matches
- File-change monitoring only runs while the app is open. A background refresh on launch catches changes made while it was closed
- The menu bar provides Open Filewise and Search Files actions; a configurable global shortcut is not yet implemented
- App bundle sizes sum regular files within the bundle; unreadable bundles show an unavailable size and are excluded from size-based suggestions
- Cleanup cards show review candidates and their total size, not guaranteed recoverable space
- The VoiceOver tree has been checked in code; a spoken pass by a person and a visual focus-ring review remain before release
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
