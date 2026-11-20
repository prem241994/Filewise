#!/bin/zsh
# Captures the UI in light and dark mode against a disposable sample folder.
# Usage: scripts/snapshot-ui.sh [output-dir] [steps]
# Steps are comma-separated name:category[:query][:select|play|scroll] entries.
# Set FILEWISE_LICENSE (trial:<days>|expired|unlocked; default trial:5) for the trial state.
# Set FILEWISE_SNAPSHOT_SOURCE to capture a copy of an existing folder.
set -e

source "${0:A:h}/common.sh"
app_dir="$build_dir/snapshot/Filewise.app"
output=${1:-$build_dir/snapshots}
steps=${2:-"welcome:Welcome,home:Home,duplicates:Duplicates::select,search:Home:report,cleanup:Clean Up::select"}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/filewise-snapshot.XXXXXX")
db_dir=$(mktemp -d "${TMPDIR:-/tmp}/filewise-snapshot-db.XXXXXX")
trap 'rm -rf "$fixture" "$db_dir"' EXIT

mkdir -p "$app_dir/Contents/MacOS" "$output"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Resources"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.filewise.snapshot" "$app_dir/Contents/Info.plist"
build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${app_frameworks[@]}" "${core_link_flags[@]}" -D FILEWISE_SNAPSHOT -D FILEWISE_LICENSE_TESTING \
    "$project_dir"/Sources/Filewise/**/*.swift "$project_dir"/tools/SnapshotHook.swift \
    -o "$app_dir/Contents/MacOS/Filewise"
codesign --force --sign - "$app_dir" >/dev/null

# FILEWISE_SNAPSHOT_SOURCE captures a copy of an existing folder instead.
if [[ -n $FILEWISE_SNAPSHOT_SOURCE ]]; then
    ditto "$FILEWISE_SNAPSHOT_SOURCE" "$fixture"
else
    # Sample library: documents, a duplicate, old and new screenshots, downloads
    # with origins, and sparse large media files.
    mkdir -p "$fixture"/{Documents,Downloads,Desktop,Media}
    echo "Quarterly planning" > "$fixture/Documents/Q3 Planning.pdf"
    cp "$fixture/Documents/Q3 Planning.pdf" "$fixture/Downloads/Q3 Planning (1).pdf"
    echo "budget" > "$fixture/Documents/Budget 2026.xlsx"
    echo "# Notes" > "$fixture/Documents/Meeting notes.md"
    echo "report" > "$fixture/Documents/Annual report draft.docx"
    echo "kit" > "$fixture/Downloads/Brand Kit.zip"
    echo "logo" > "$fixture/Downloads/Logo final.png"
    echo "slides" > "$fixture/Downloads/Pitch deck.key"
    dd if=/dev/zero of="$fixture/Downloads/Installer.dmg" bs=1 count=0 seek=157m 2>/dev/null
    dd if=/dev/zero of="$fixture/Media/Holiday trip.mov" bs=1 count=0 seek=231m 2>/dev/null
    echo "song" > "$fixture/Media/Morning song.mp3"
    echo "old" > "$fixture/Desktop/Screenshot 2026-09-01 at 10.12.03.png"
    echo "new" > "$fixture/Desktop/Screenshot 2026-11-16 at 09.00.00.png"
    canva=$(python3 -c 'import plistlib;print(plistlib.dumps(["https://www.canva.com/design/x"],fmt=plistlib.FMT_BINARY).hex())')
    github=$(python3 -c 'import plistlib;print(plistlib.dumps(["https://github.com/x/y/releases"],fmt=plistlib.FMT_BINARY).hex())')
    xattr -wx com.apple.metadata:kMDItemWhereFroms "$canva" "$fixture/Downloads/Brand Kit.zip"
    xattr -wx com.apple.metadata:kMDItemWhereFroms "$canva" "$fixture/Downloads/Logo final.png"
    xattr -wx com.apple.metadata:kMDItemWhereFroms "$github" "$fixture/Downloads/Installer.dmg"
    touch -t 202609011012 "$fixture/Desktop/Screenshot 2026-09-01 at 10.12.03.png" "$fixture/Downloads/Brand Kit.zip" "$fixture/Downloads/Installer.dmg"
fi

for appearance in light dark; do
    FILEWISE_TEST_DATABASE_DIRECTORY="$db_dir/$appearance" FILEWISE_SNAPSHOT_DIR="$output" \
    FILEWISE_SNAPSHOT_FOLDER="$fixture" FILEWISE_SNAPSHOT_APPEARANCE="$appearance" \
    FILEWISE_SNAPSHOT_STEPS="$steps" FILEWISE_LICENSE=${FILEWISE_LICENSE:-trial:5} \
    "$app_dir/Contents/MacOS/Filewise" >/dev/null 2>&1 || true
done
echo "Snapshots in $output"
