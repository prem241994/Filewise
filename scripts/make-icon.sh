#!/bin/zsh
# Renders tools/AppIcon.swift into Resources/AppIcon-1024.png and the
# Resources/AppIcon.icns that build.sh puts in the app. Rerun after changing
# the icon's drawing, and commit both files.
set -e
source "${0:A:h}/common.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/filewise-icon.XXXXXX")
trap 'rm -rf "$work"' EXIT

swiftc "${swift_flags[@]}" -framework SwiftUI -framework AppKit \
    "$project_dir/tools/AppIcon.swift" -o "$work/render-icon"
"$work/render-icon" "$project_dir/Resources/AppIcon-1024.png"

iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$project_dir/Resources/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$project_dir/Resources/AppIcon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$project_dir/Resources/AppIcon.icns"
echo "Wrote Resources/AppIcon-1024.png and Resources/AppIcon.icns"
