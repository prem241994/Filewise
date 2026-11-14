#!/bin/zsh
set -e

project_dir=${0:A:h:h}
app_dir="$project_dir/.build/Filewise.app"
archive="$project_dir/.build/Filewise-local.zip"
package_tmp=$(mktemp -d "${TMPDIR:-/tmp}/filewise-package.XXXXXX")
trap 'rm -rf "$package_tmp"' EXIT

"$project_dir/scripts/build.sh"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$package_tmp/Filewise-local.zip"
mkdir "$package_tmp/unpacked"
ditto -x -k "$package_tmp/Filewise-local.zip" "$package_tmp/unpacked"
codesign --verify --deep --strict "$package_tmp/unpacked/Filewise.app"
mv -f "$package_tmp/Filewise-local.zip" "$archive"
echo "Packaged $archive"
