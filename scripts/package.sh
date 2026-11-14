#!/bin/zsh
set -e

project_dir=${0:A:h:h}
app_dir="$project_dir/.build/Filewise.app"
archive="$project_dir/.build/Filewise-local.zip"

"$project_dir/scripts/build.sh"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"
echo "Packaged $archive"
