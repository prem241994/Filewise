#!/bin/zsh
set -e

project_dir=${0:A:h:h}
build_dir="$project_dir/.build"
app_dir="$build_dir/Filewise.app"
sdk_dir=${FILEWISE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}
target_arch=$(uname -m)

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$build_dir/module-cache"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

CLANG_MODULE_CACHE_PATH="$build_dir/module-cache" swiftc \
    -sdk "$sdk_dir" \
    -module-cache-path "$build_dir/module-cache" \
    -target "${target_arch}-apple-macosx14.0" \
    -swift-version 5 \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework CryptoKit \
    -framework QuickLook \
    -framework QuickLookUI \
    -lsqlite3 \
    "$project_dir"/Sources/Filewise/**/*.swift \
    -o "$app_dir/Contents/MacOS/Filewise"

codesign --force --deep --sign - "$app_dir"
echo "Built $app_dir"
