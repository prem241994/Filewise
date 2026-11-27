#!/bin/zsh
# Builds the made-up "My Files" demo folder used for marketing screenshots and
# the demo video (tools/DemoFolder.swift). Dates are relative to today.
# Usage: scripts/make-demo-folder.sh [output-folder]   (default: .build/demo/My Files)
set -e
source "${0:A:h}/common.sh"
output=${1:-"$build_dir/demo/My Files"}
mkdir -p "$build_dir/demo"
swiftc "${swift_flags[@]}" -framework AppKit "$project_dir/tools/DemoFolder.swift" -o "$build_dir/demo/make-demo-folder"
"$build_dir/demo/make-demo-folder" "$output"
