# Filewise

Filewise is a native Mac app for finding files and reviewing cleanup candidates in one place. Its dashboard has a single search field, library categories, cleanup cards, and recent files. The development build scans a folder chosen by the user, searches file metadata, and identifies identical files. File metadata is stored in a local SQLite index under Application Support so results can appear from the previous scan while a background refresh runs.

## Open in VS Code

Open `/Users/premkumar/Desktop/Filewise` in VS Code. Use **Terminal → Run Build Task** for the default build task, or choose **Run Filewise** from **Terminal → Run Task**.

The same commands work in the integrated terminal:

```sh
./scripts/build.sh
open .build/Filewise.app
```

For a local copy, run `zsh scripts/package.sh` to build and create `.build/Filewise-local.zip`. The script extracts the archive and verifies its app signature before replacing the previous package. This build is ad-hoc signed for development and is not notarized for distribution to other Macs.

The build script uses the active macOS SDK selected by `xcrun` and builds for the current Mac's architecture. It invokes the Swift compiler directly; the local Swift Package Manager installation currently fails before compiling. The `Package.swift` manifest is available once the command line tools are repaired or Xcode is installed.

## Code layout

- `Sources/FilewiseCore` has no UI code: the file model, the SQLite index (`FileIndex`), folder scanning and duplicate detection (`FolderScanner`), search phrase parsing (`FileSearch`), journaled Trash and Undo (`TrashService`), and the folder watcher. It can be built and tested without SwiftUI.
- `Sources/Filewise` is the app: SwiftUI views and the `Library` view model. `Library` runs on the main actor; it starts Core work on background tasks and applies only the results.

Both modules use the Swift 6 language mode with complete data-race checking. `scripts/common.sh` holds the shared compiler settings and builds `FilewiseCore` as a static library that the app and the tests link against.

If the active SDK and Swift compiler are incompatible, select a compatible installed SDK for the build and test scripts, for example: `export FILEWISE_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`.

## Use

Choose a folder, then browse the library cards or search by name. The window follows the system light or dark appearance. Results appear in a sortable table (click a column header); select one file to see its details, why it is suggested for cleanup, and any identical copies in the inspector, or select several to review them together. Use **File → Choose Folder…** (⌘O), **View → Refresh Library** (⌘R), and **Edit → Restore Last Trashed Files**. You can try `pdf from last week`, `screenshots in Downloads`, or `recent`. Double-click a result to open it, or right-click to show it in Finder. Filewise remembers the selected folder and scans it again when the app opens. A running scan shows its file count and can be cancelled.

Application bundles within the selected folder appear as single items in Apps. Their size is the sum of readable regular files inside the bundle; if the contents cannot be fully read, the size is shown as unavailable.

While Filewise is running, its menu bar icon provides Open Filewise and Quit Filewise actions.

You can also drop a folder onto the Filewise window to select and scan it.

The app reads file metadata and hashes possible duplicates within the selected folder. It watches the folder for changes and refreshes the index when files are added or removed. Each refresh enumerates the selected folder, reuses hashes for unchanged files, and updates only changed index rows. Cleanup cards are review views; the app does not upload or permanently delete files.

When you choose **Move to Trash**, Filewise records each move as it happens and stops if it cannot save an Undo record. Undo for the latest recorded batch returns after reopening the selected folder, including after cancellation. If a move is interrupted before its Trash location is saved, check macOS Trash manually. The size shown in progress is the size moved to Trash; macOS does not reclaim that disk space until Trash is emptied.

## Check the UI

Run `./scripts/snapshot-ui.sh [output-dir]` to capture the main screens in light and dark mode against a disposable sample folder (default output: `.build/snapshots`). It builds a separate copy of the app with a development-only capture hook from `tools/SnapshotHook.swift`; the shipping build never includes it. It uses an isolated index and its own preferences, so your library is untouched.

## Check the cleanup flow

Run `./scripts/test-trash-cancellation.sh` to exercise a disposable temporary folder. The check cancels partway through a batch, verifies the SQLite index and Undo record, restores the files, and removes its fixture.

Run `./scripts/test-scan-search.sh` to test scanning, cancellation, FTS search, missing or restricted folders, and recovery after a folder disappears and returns, using disposable files. Both integration checks use isolated temporary SQLite databases and remove their fixtures afterward.

Run `./scripts/test-duplicates.sh` to check which copy each "Select Extra Copies" rule keeps (oldest, newest, shortest name, or the copy in a chosen folder).

Run `./scripts/test-trash-safety.sh` for isolated checks of partial cancellation, failed Undo writes, rollback, and restart recovery.

Run `./scripts/test-index-health.sh` to check migration of an older index, preservation of its Trash Undo records, and safe handling of a corrupt database. When an index is unavailable, use **Rebuild Index** in the sidebar to clear and rescan recoverable file metadata while retaining Trash Undo records. If the database itself cannot be read, it is left untouched; **Show Index Folder** opens its location for manual recovery. **Export Undo Records** attempts a read-only JSON export of any readable records, and indicates a partial export; it does not repair the database or automatically restore files.

Run `./scripts/benchmark-scan.sh` for an isolated 10,000-file metadata scan and unchanged refresh baseline, including peak process memory. Set `FILEWISE_BENCHMARK_FILES` to change the fixture size. This baseline uses unique-sized files and does not measure duplicate hashing.

GitHub Actions builds and verifies the local package, then runs the index health, scan/search, and Trash safety checks on macOS for pushes and pull requests. The separate Trash cancellation check requires access to the macOS Trash and is intended for a local session with that permission.

## Project state

See [roadmap.md](roadmap.md) and [project-status.md](project-status.md).
