#!/bin/zsh
set -e
source "${0:A:h}/common.sh"

app_dir="$build_dir/Filewise.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${app_frameworks[@]}" "${core_link_flags[@]}" \
    "$project_dir"/Sources/Filewise/**/*.swift \
    -o "$app_dir/Contents/MacOS/Filewise"

# Sandboxed, as the App Store requires. Tests and the snapshot build are not.
codesign --force --sign - --entitlements "$project_dir/Resources/Filewise.entitlements" "$app_dir"
echo "Built $app_dir"
