#!/bin/zsh
set -e

project_dir=${0:A:h:h}
app_dir="$project_dir/.build/Filewise.app"
archive="$project_dir/.build/Filewise-local.zip"
package_tmp=$(mktemp -d "${TMPDIR:-/tmp}/filewise-package.XXXXXX")
trap 'rm -rf "$package_tmp"' EXIT

"$project_dir/scripts/build.sh"
codesign --verify --deep --strict "$app_dir"
# Fail if the app lost its sandbox, or gained network access.
entitlements=$(codesign -d --entitlements - --xml "$app_dir" 2>/dev/null)
[[ $entitlements == *com.apple.security.app-sandbox* ]] || { echo "App Sandbox entitlement missing" >&2; exit 1; }
[[ $entitlements != *com.apple.security.network* ]] || { echo "Unexpected network entitlement" >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$package_tmp/Filewise-local.zip"
mkdir "$package_tmp/unpacked"
ditto -x -k "$package_tmp/Filewise-local.zip" "$package_tmp/unpacked"
codesign --verify --deep --strict "$package_tmp/unpacked/Filewise.app"
mv -f "$package_tmp/Filewise-local.zip" "$archive"
echo "Packaged $archive"
