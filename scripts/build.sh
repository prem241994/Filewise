#!/bin/zsh
set -e
source "${0:A:h}/common.sh"

app_dir="$build_dir/Filewise.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"

# FILEWISE_LICENSE_TESTING=1 builds a development copy whose trial state comes
# from FILEWISE_LICENSE=trial:<days>|expired|unlocked at launch. Never ship it.
license_flags=()
[[ $FILEWISE_LICENSE_TESTING == 1 ]] && license_flags=(-D FILEWISE_LICENSE_TESTING)

build_core "$build_dir/core"
swiftc "${swift_flags[@]}" "${app_frameworks[@]}" "${core_link_flags[@]}" "${license_flags[@]}" \
    "$project_dir"/Sources/Filewise/**/*.swift \
    -o "$app_dir/Contents/MacOS/Filewise"

# Sandboxed, as the App Store requires. Tests and the snapshot build are not.
codesign --force --sign - --entitlements "$project_dir/Resources/Filewise.entitlements" "$app_dir"
echo "Built $app_dir"
