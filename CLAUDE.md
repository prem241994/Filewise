# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Filewise is a native macOS (14+) SwiftUI app that indexes a user-chosen folder into a local SQLite database, searches it, and suggests cleanup candidates (duplicates, large files, old screenshots/downloads). It is intended for sale on the Mac App Store, so it has to be release quality, and data safety (Trash/Undo) matters most.

## Build and test

Swift Package Manager is **not used** because it is broken on the development Mac. `Package.swift` mirrors the build but nothing runs it. Every build goes through zsh scripts that call `swiftc` directly, using shared settings in `scripts/common.sh`. If you add a module, source folder, framework, or compiler flag, update both `scripts/common.sh` and `Package.swift`.

```sh
./scripts/build.sh                 # builds .build/Filewise.app, ad-hoc signed with the sandbox entitlements
open .build/Filewise.app
zsh scripts/package.sh             # build + codesign/entitlement checks + .build/Filewise-local.zip (what CI runs)
```

If the active SDK doesn't match the compiler (it doesn't on this Mac), set this first:

```sh
export FILEWISE_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
```

There is no XCTest. Each test is a standalone `@main` harness in `tests/`. It compiles together with the FilewiseCore static library, and sometimes with the app's `Sources/Filewise/ViewModels/*.swift`. A harness prints `PASS:` or `FAIL:` and exits non-zero on failure. Run one test by running its script:

| Script | Covers |
|---|---|
| `scripts/test-license.sh` | trial length, day counting, expiry, unlock gating (Core only) |
| `scripts/test-duplicates.sh` | keep rules for "Select Extra Copies" (Core only) |
| `scripts/test-scan-search.sh` | scanning, cancellation, FTS search, missing/restricted folders, settings |
| `scripts/test-index-health.sh` | schema migration, Undo-record preservation, corrupt DB handling |
| `scripts/test-trash-safety.sh` | Trash journaling, failed Undo writes, rollback, restart recovery |
| `scripts/test-trash-cancellation.sh` | real macOS Trash; **local only** (needs Trash access, not in CI) |
| `scripts/benchmark-scan.sh` | 10k-file scan/refresh timing and peak RSS (`FILEWISE_BENCHMARK_FILES` sets the size) |

CI (`.github/workflows/macos.yml`) runs `package.sh` plus the license, duplicates, index-health, scan-search, and trash-safety scripts. To add a test, write `tests/FooHarness.swift` and a matching `scripts/test-foo.sh` modeled on an existing one, then add a step to the workflow.

Harnesses that touch the index must set `FILEWISE_TEST_DATABASE_DIRECTORY` to a temp dir (the scripts already do). Otherwise `FileIndex` writes to the real index in `~/Library/Application Support/Filewise/`. The sandboxed app uses its container instead, at `~/Library/Containers/app.filewise.desktop/Data/Library/Application Support/Filewise/`.

### App icon

`tools/AppIcon.swift` draws the icon as a SwiftUI view on the macOS icon grid: an 824-point rounded square on a 1024 canvas. `./scripts/make-icon.sh` renders it to `Resources/AppIcon-1024.png` and `Resources/AppIcon.icns`, and `build.sh` copies the `.icns` into the app (`CFBundleIconFile`). Change the drawing, rerun the script, and commit both outputs. App Store submission will also need an asset-catalog `AppIcon` built from the 1024 PNG, which requires Xcode's `actool`.

### UI verification

`./scripts/snapshot-ui.sh [output-dir] [steps]` builds a separate app copy with `-D FILEWISE_SNAPSHOT` and `tools/SnapshotHook.swift`. It runs that copy against a generated sample folder and writes light and dark PNGs to `.build/snapshots`. It uses an isolated index and the bundle ID `app.filewise.snapshot`. Steps are comma-separated `name:category[:query][:select|play|scroll]` entries, and the category `Settings` captures the Settings window. Use this to check UI changes visually. Code under `#if FILEWISE_SNAPSHOT` must never be needed by the shipping build.

For **accessibility**, a step `name:Accessibility:<category>` writes `name-<appearance>.txt` instead of a PNG. It lists what VoiceOver can reach: role, spoken name, value, and actions, read through the AX API on the app itself, so no Accessibility permission is needed. Add `:ax` as the third field of a `Welcome`, `Paywall`, or `Settings` step for the same dump. Lines starting with `!` are unnamed buttons or images. The only acceptable ones are macOS's own scroll-bar arrows and window buttons. Conventions: decorative icons get `.accessibilityHidden(true)`, page and section titles get `.isHeader`, and file tiles and rows use `fileAccessibilityActions` (Open, Quick Look, Show in Finder, Move to Trash).

## Toolchain constraints

- Both modules compile with `-swift-version 6` and complete data-race checking. The code must build with no concurrency errors.
- CI runs on `macos-15` with **Swift 6.1**, while the local Mac has a newer Swift. Don't use Swift 6.2+ features such as `@concurrent`, `isolated deinit`, `nonisolated(nonsending)`, or default main-actor isolation.

## Architecture

Two modules:

- **`Sources/FilewiseCore`**: no UI, links only Foundation and sqlite3. Most services are stateless `public enum` namespaces of static functions that are safe to call from any thread:
  - `FileIndex`: the SQLite database (raw `sqlite3` C API, no wrapper). Tables: `files`, the FTS5 `files_fts` (name/extension/path search), `search_meta` (per-folder metadata such as last scan time), and `trash_manifest` (the Undo journal). Schema changes are migrations inside a transactional `initializeSchema`. `test-index-health.sh` checks older-schema migration, and the migration must keep `trash_manifest` rows intact. The DB also stores derived data (last-opened date, origin, SHA-256 hashes) so refreshes can reuse it for unchanged files.
  - `FolderScanner`: enumerates the folder and updates only changed rows. It hashes only files that share a size, to find duplicates. It treats `.app` bundles as single items and honors `CleanupSettings.ignoredPaths`.
  - `FileSearch`: parses natural-language queries ("pdfs from last week", "large videos", "screenshots in Downloads") into type, date, size, and location filters plus FTS terms.
  - `TrashService`: journals each move in `trash_manifest` before and after it happens. It stops if it can't write a journal entry, tries to roll back, and restores the latest batch (including after a crash, on reopening the folder). `TrashOperations` injects the file-system calls so tests can simulate failures.
  - `DuplicateSelection` / `KeepRule`: chooses which copy of a duplicate set to keep.
  - `FileWatcher`: FSEvents-based and debounced; it triggers refreshes.
  - `ScanToken`: lock-backed `Sendable` cancellation flag that the main actor shares with background work.
  - `PathPrefixes`: returns both the given and canonical forms of a folder path (`/var` vs `/private/var`). FSEvents reports canonical paths, so **any path-prefix matching must use it**.
  - `CleanupSettings.current`: process-wide, lock-protected settings (large-file threshold, "old" age, ignored folders). The scanner, rules, and watcher read it. The app sets it from `AppSettings` (UserDefaults), and tests set it directly.

- **`Sources/Filewise`**: the SwiftUI app.
  - `ViewModels/Library.swift` is the central `@MainActor ObservableObject`. It owns the selected folder (a security-scoped bookmark), scan, search, selection, trash, and undo state. Blocking work goes through `Library.background { … }` (a `Task.detached`), and only the results come back to the main actor. Each scan or trash run gets a `ScanToken` and an ID, and results from an older run are dropped (`isCurrent`). Search is debounced in a cancellable `searchTask`.
  - `Views/` uses a `NavigationSplitView` with a sidebar, a Home dashboard (library and cleanup cards), a sortable `Table` of results, and a detail inspector. Shared styling and file actions live in `Views/Theme.swift`.
  - `Services/` holds the app-side caches (icons, QuickLook thumbnails).

### App Sandbox

`build.sh` signs the app with `Resources/Filewise.entitlements`: sandbox, user-selected read-write, app-scope bookmarks, and Downloads read-write. There is no network entitlement, and `package.sh` fails the build if one appears or the sandbox entitlement goes missing. Test harnesses and the snapshot build are **not** sandboxed, so sandbox-only behavior has to be checked by hand in `.build/Filewise.app`.

- `Services/FolderAccess.swift` handles folder access. Every granted folder is stored as a security-scoped bookmark keyed by path. `grantedURL(for:)` returns a readable URL, or opens an open panel aimed at the folder to ask for access. Outside the sandbox it is a no-op. Library saves only folder *paths* and resolves them through `FolderAccess`.
- `Library.folder`'s `didSet` holds `startAccessingSecurityScopedResource()` for as long as a folder is selected, because Trash, Undo, Quick Look, thumbnails, and the watcher all need it. Don't move file work outside the selected folder without a grant.
- Use `FolderAccess.homeDirectory` for the user's real home. In the sandbox, `NSHomeDirectory()` and `FileManager.urls(for:in:)` point into the container.
- Testing confirmed that Undo restore from `~/.Trash` works under the sandbox, both in the same launch and after a relaunch, without extra bookmarks for the trashed files. It has not been checked for folders on other volumes, which use `/Volumes/…/.Trashes`.

### Trial and unlock

The business model is a 7-day free trial, then a $4.99 non-consumable in-app purchase (`License.unlockProductID`), using StoreKit 2 with no server.
- **App Review Guideline 3.1.1:** the trial is a free ($0) non-consumable named "7-day Trial" (`License.trialProductID`) that the user starts with a button. Before it starts, the app must show the trial's length, what stops working, and the price. `Store.trialTerms` is that text, shown on the welcome page and in the sheet. Don't start the trial silently, and keep those terms accurate if gating changes.
- `FilewiseCore/Models/License.swift` holds the pure trial math (`LicenseStatus`: checking, notStarted, trial, expired, unlocked). `Services/Store.swift` (`@MainActor`, shared from `FilewiseApp`) takes the trial start from the trial product's purchase date and the unlock from `Transaction.currentEntitlements`, and listens to `Transaction.updates`. When the trial product is unavailable (not an App Store install), Start Free Trial saves a local start date instead.
- **Only cleanup actions are gated.** Move to Trash (`ContentView.requestTrash`) and Select Extra Copies (`ResultsView`) go through `store.requireUnlock`, which shows `PaywallView` when expired. Search, browsing, suggestions, and **Undo** must stay free. Never gate restore.
- `FILEWISE_LICENSE_TESTING=1 ./scripts/build.sh` compiles in an override read from `FILEWISE_LICENSE=new|trial:<days>|expired|unlocked` at launch, and test purchases succeed instantly. The snapshot build always has it (default `trial:5`), and the `Paywall` snapshot step captures the sheet. The shipping build must not contain it: `strings` on the binary should not find `FILEWISE_LICENSE`.
- Real purchases can only be tested once both products exist in App Store Connect, through a sandbox account. There is no `.storekit` configuration because there is no Xcode project.

The integration harnesses drive `Library` itself, which is why they compile the ViewModels sources together with AppKit and SwiftUI.

## Product constraints

- **No network code, analytics, crash SDKs, or accounts**. The App Store privacy label will be "Data Not Collected". Features must work inside the App Sandbox without a network entitlement and keep access to user folders through security-scoped bookmarks.
- Filewise never deletes files permanently. It only moves them to the macOS Trash, with a recorded Undo. UI text says "moved to Trash", not "space freed".
- `roadmap.md` and `project-status.md` record the project's state and plans. When you finish a feature, add it to `project-status.md`.

## Conventions

- Commit messages: an imperative summary line, then a body paragraph explaining the change in prose, including what the tests cover and any benchmark impact.
- Work on feature branches. `main` is kept green in CI.
