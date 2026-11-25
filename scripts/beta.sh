#!/bin/zsh
# Builds a tester copy of Filewise: universal (Apple silicon and Intel),
# sandboxed, with everything unlocked (-D FILEWISE_BETA), because testers
# can't buy through the App Store. Writes .build/Filewise-Beta.zip containing
# the app and a short "How to open" note. Signed ad hoc, so testers must allow
# it once in System Settings. Never upload this build to the App Store.
set -e
source "${0:A:h}/common.sh"

beta_dir="$build_dir/beta"
app_dir="$beta_dir/Filewise.app"
rm -rf "$beta_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

base_flags=("${swift_flags[@]}")
slices=()
for arch in arm64 x86_64; do
    # Same settings as common.sh, but for this architecture.
    swift_flags=("${(@)base_flags/#$(uname -m)-apple-macosx14.0/$arch-apple-macosx14.0}")
    build_core "$beta_dir/core-$arch"
    swiftc "${swift_flags[@]}" "${app_frameworks[@]}" "${core_link_flags[@]}" -D FILEWISE_BETA \
        "$project_dir"/Sources/Filewise/**/*.swift \
        -o "$beta_dir/Filewise-$arch"
    slices+=("$beta_dir/Filewise-$arch")
done
lipo -create "${slices[@]}" -output "$app_dir/Contents/MacOS/Filewise"

codesign --force --sign - --entitlements "$project_dir/Resources/Filewise.entitlements" "$app_dir"
codesign --verify --deep --strict "$app_dir"
entitlements=$(codesign -d --entitlements - --xml "$app_dir" 2>/dev/null)
[[ $entitlements == *com.apple.security.app-sandbox* ]] || { echo "App Sandbox entitlement missing" >&2; exit 1; }
[[ $entitlements != *com.apple.security.network* ]] || { echo "Unexpected network entitlement" >&2; exit 1; }
if strings "$app_dir/Contents/MacOS/Filewise" | grep -q FILEWISE_LICENSE; then
    echo "License testing override found in the beta build" >&2; exit 1
fi

package="$beta_dir/Filewise Beta"
mkdir -p "$package"
ditto "$app_dir" "$package/Filewise.app"
cat > "$package/How to open.txt" <<'EOF'
Filewise beta: thank you for testing!

Filewise finds files on your Mac and suggests what to clean up. It only ever
moves files to the Trash, and every move can be undone.

Needs macOS 14 (Sonoma) or later, on Apple silicon or Intel.

How to open it the first time
1. Drag Filewise into your Applications folder.
2. Double-click it. macOS will say it can't check the app for malicious
   software, because this test copy isn't from the App Store yet. Click Done.
3. Open System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to the message about Filewise. Confirm with your password.
   (On macOS 14 you can instead right-click Filewise and choose Open.)
4. After that, it opens normally.

What I'd love to hear
- What was confusing or slow?
- Did search find what you were looking for?
- Would you pay for it, and would a "less than a coffee" one-time price feel fair?

Filewise works offline and collects no data.
EOF
rm -f "$build_dir/Filewise-Beta.zip"
ditto -c -k --sequesterRsrc --keepParent "$package" "$build_dir/Filewise-Beta.zip"
lipo -archs "$app_dir/Contents/MacOS/Filewise"
echo "Packaged $build_dir/Filewise-Beta.zip"
