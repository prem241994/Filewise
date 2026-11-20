# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Filewise is a native macOS (14+) SwiftUI app that indexes a user-chosen folder into a local SQLite database, searches it, and suggests cleanup candidates (duplicates, large files, old screenshots/downloads). It is intended for sale on the Mac App Store, so it has to be release quality, and data safety (Trash/Undo) matters most.

## Build and test

Swift Package Manager is **not used** because it is broken on the development Mac. `Package.swift` mirrors the build but nothing runs it. Every build goes through zsh scripts that call `swiftc` directly, using shared settings in `scripts/common.sh`. If you add a module, source folder, framework, or compiler flag, update both `scripts/common.sh` and `Package.swift`.

```sh
./scripts/build.sh                 # builds and ad-hoc signs .build/Filewise.app
open .build/Filewise.app
zsh scripts/package.sh             # build + codesign verify + .build/Filewise-local.zip (what CI runs)
```

If the active SDK doesn't match the compiler (it doesn't on this Mac), set this first:

```sh
export FILEWISE_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
```

There is no XCTest. Each test is a standalone `@main` harness in `tests/`. It compiles together with the FilewiseCore static library, and sometimes with the app's `Sources/Filewise/ViewModels/*.swift`. A harness prints `PASS:` or `FAIL:` and exits non-zero on failure. Run one test by running its script:

| Script | Covers |
|---|---|
| `scripts/test-duplicates.sh` | keep rules for "Select Extra Copies" (Core only) |
| `scripts/test-scan-search.sh` | scanning, cancellation, FTS search, missing/restricted folders, settings |
| `scripts/test-index-health.sh` | schema migration, Undo-record preservation, corrupt DB handling |
| `scripts/test-trash-safety.sh` | Trash journaling, failed Undo writes, rollback, restart recovery |
| `scripts/test-trash-cancellation.sh` | real macOS Trash; **local only** (needs Trash access, not in CI) |
| `scripts/benchmark-scan.sh` | 10k-file scan/refresh timing and peak RSS (`FILEWISE_BENCHMARK_FILES` sets the size) |

CI (`.github/workflows/macos.yml`) runs `package.sh` plus the duplicates, index-health, scan-search, and trash-safety scripts. To add a test, write `tests/FooHarness.swift` and a matching `scripts/test-foo.sh` modeled on an existing one, then add a step to the workflow.

Harnesses that touch the index must set `FILEWISE_TEST_DATABASE_DIRECTORY` to a temp dir (the scripts already do). Otherwise `FileIndex` writes to the real `~/Library/Application Support/Filewise/index.sqlite`.

### UI verification

`./scripts/snapshot-ui.sh [output-dir] [steps]` builds a separate app copy with `-D FILEWISE_SNAPSHOT` and `tools/SnapshotHook.swift`. It runs that copy against a generated sample folder and writes light and dark PNGs to `.build/snapshots`. It uses an isolated index and the bundle ID `app.filewise.snapshot`. Steps are comma-separated `name:category[:query][:select|play|scroll]` entries, and the category `Settings` captures the Settings window. Use this to check UI changes visually. Code under `#if FILEWISE_SNAPSHOT` must never be needed by the shipping build.

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

The integration harnesses drive `Library` itself, which is why they compile the ViewModels sources together with AppKit and SwiftUI.

## Product constraints

- **No network code, analytics, crash SDKs, or accounts**. The App Store privacy label will be "Data Not Collected". Features must work inside the App Sandbox without a network entitlement and keep access to user folders through security-scoped bookmarks.
- Filewise never deletes files permanently. It only moves them to the macOS Trash, with a recorded Undo. UI text says "moved to Trash", not "space freed".
- `roadmap.md` and `project-status.md` record the project's state and plans. When you finish a feature, add it to `project-status.md`.

## Conventions

- Commit messages: an imperative summary line, then a body paragraph explaining the change in prose, including what the tests cover and any benchmark impact.
- Work on feature branches. `main` is kept green in CI.
