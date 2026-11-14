#!/bin/zsh
set -e
project_dir=${0:A:h:h}
build_dir="$project_dir/.build"
sdk_dir=${FILEWISE_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}
target_arch=$(uname -m)
filewise_test_db_dir=$(mktemp -d "${TMPDIR:-/tmp}/filewise-trash-safety.XXXXXX")
trap 'rm -rf "$filewise_test_db_dir"' EXIT
mkdir -p "$build_dir/module-cache"
swiftc -sdk "$sdk_dir" -module-cache-path "$build_dir/module-cache" \
    -target "${target_arch}-apple-macosx14.0" -swift-version 5 -parse-as-library \
    -framework SwiftUI -framework AppKit -framework CryptoKit -lsqlite3 \
    "$project_dir"/Sources/Filewise/Models/*.swift \
    "$project_dir"/Sources/Filewise/Services/*.swift \
    "$project_dir"/Sources/Filewise/ViewModels/*.swift \
    "$project_dir"/tests/TrashSafetyHarness.swift -o "$build_dir/trash-safety-test"
FILEWISE_TEST_DATABASE_DIRECTORY="$filewise_test_db_dir" "$build_dir/trash-safety-test"
